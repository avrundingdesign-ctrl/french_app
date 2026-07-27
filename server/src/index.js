// CloudFlare Worker: Proxy zwischen App und Anthropic.
//
// Warum es das gibt: Ein API-Key, der in der App steckt, ist aus dem Binary
// auslesbar und steht außerdem im Klartext im `x-api-key`-Header — jeder mit
// einem Debug-Proxy könnte auf fremde Rechnung chatten. Hier liegt der Key
// serverseitig, ist ohne App-Update rotierbar, und pro Gerät gilt ein Limit.
//
// Zugang nur mit gültiger App-Attest-Assertion: Die Anfrage muss aus einer
// echten, unveränderten Instanz dieser App auf echter Apple-Hardware kommen.

import { verifyAttestation, verifyAssertion, b64ToBytes, bytesToB64 } from './attest.js'
import { validateRequest } from './prompt.js'

const CHALLENGE_TTL_SECONDS = 300
const DEFAULT_DAILY_LIMIT = 40

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url)
    try {
      if (request.method === 'GET' && url.pathname === '/v1/attest/challenge') {
        return await issueChallenge(env)
      }
      if (request.method === 'POST' && url.pathname === '/v1/attest/register') {
        return await register(request, env)
      }
      if (request.method === 'POST' && url.pathname === '/v1/chat') {
        return await chat(request, env, ctx)
      }
      return fail(404, 'not_found', 'Unbekannter Endpunkt.')
    } catch (error) {
      console.error('unhandled', error)
      return fail(500, 'internal', 'Unerwarteter Serverfehler.')
    }
  },
}

// MARK: - Antworten

function ok(body) {
  return new Response(JSON.stringify(body), {
    headers: { 'content-type': 'application/json' },
  })
}

function fail(status, code, message) {
  return new Response(JSON.stringify({ error: { code, message } }), {
    status,
    headers: { 'content-type': 'application/json' },
  })
}

// MARK: - Registrierung

async function issueChallenge(env) {
  const raw = crypto.getRandomValues(new Uint8Array(32))
  const challenge = bytesToB64(raw)
  await env.DEVICES.put(`challenge:${challenge}`, '1', {
    expirationTtl: CHALLENGE_TTL_SECONDS,
  })
  return ok({ challenge, expiresIn: CHALLENGE_TTL_SECONDS })
}

async function register(request, env) {
  const keyId = request.headers.get('x-attest-key-id')
  if (!keyId) return fail(400, 'attest_failed', 'keyId fehlt.')

  const payload = await request.json().catch(() => null)
  if (!payload?.attestation || !payload?.challenge) {
    return fail(400, 'attest_failed', 'Attestation oder Challenge fehlt.')
  }

  // Challenge muss von uns stammen und darf nur einmal gelten.
  const challengeKey = `challenge:${payload.challenge}`
  if (!(await env.DEVICES.get(challengeKey))) {
    return fail(400, 'attest_failed', 'Challenge ist abgelaufen. Bitte nochmal versuchen.')
  }
  await env.DEVICES.delete(challengeKey)

  try {
    const { publicKeyRaw, counter } = await verifyAttestation({
      attestation: b64ToBytes(payload.attestation),
      keyId,
      challenge: payload.challenge,
      teamId: env.APPLE_TEAM_ID,
      bundleId: env.APPLE_BUNDLE_ID,
      allowDevelopmentEnvironment: env.ALLOW_DEV_ATTEST === 'true',
    })

    await env.DEVICES.put(
      `device:${keyId}`,
      JSON.stringify({
        publicKey: bytesToB64(publicKeyRaw),
        counter,
        registeredAt: Date.now(),
      })
    )
    return ok({ registered: true })
  } catch (error) {
    console.warn('attestation abgelehnt:', error.message)
    return fail(401, 'attest_failed', 'Die App konnte nicht verifiziert werden.')
  }
}

// MARK: - Chat

async function chat(request, env, ctx) {
  const keyId = request.headers.get('x-attest-key-id')
  const assertionHeader = request.headers.get('x-attest-assertion')
  if (!keyId || !assertionHeader) {
    return fail(401, 'attest_failed', 'Nachweis fehlt.')
  }

  const stored = await env.DEVICES.get(`device:${keyId}`, 'json')
  if (!stored) {
    // Gerät unbekannt → App soll sich neu registrieren.
    return fail(401, 'unknown_key', 'Gerät ist nicht angemeldet.')
  }

  // Rohe Bytes: Genau darüber hat die App signiert.
  const body = new Uint8Array(await request.arrayBuffer())

  let counter
  try {
    ;({ counter } = await verifyAssertion({
      assertion: b64ToBytes(assertionHeader),
      publicKeyRaw: b64ToBytes(stored.publicKey),
      storedCounter: stored.counter,
      body,
      teamId: env.APPLE_TEAM_ID,
      bundleId: env.APPLE_BUNDLE_ID,
    }))
  } catch (error) {
    console.warn('assertion abgelehnt:', error.message)
    return fail(401, 'attest_failed', 'Nachweis ungültig.')
  }

  // Zähler sofort fortschreiben, damit dieselbe Assertion nicht zweimal zählt.
  await env.DEVICES.put(
    `device:${keyId}`,
    JSON.stringify({ ...stored, counter, lastSeenAt: Date.now() })
  )

  const limit = Number(env.DAILY_MESSAGE_LIMIT ?? DEFAULT_DAILY_LIMIT)
  const usage = await bumpDailyUsage(env, keyId, limit)
  if (usage.exceeded) {
    return fail(429, 'rate_limited', `Tageslimit von ${limit} Nachrichten erreicht.`)
  }

  let plan
  try {
    plan = validateRequest(JSON.parse(new TextDecoder().decode(body)))
  } catch (error) {
    return fail(400, 'bad_request', error.message)
  }

  return callAnthropic(plan, env)
}

/// Tageslimit pro Gerät.
///
/// - Note: KV ist letztlich konsistent — bei parallelen Anfragen kann das
///   Limit leicht überschritten werden. Für ein hartes Limit wäre ein Durable
///   Object nötig; für den Kostenschutz reicht diese Genauigkeit.
async function bumpDailyUsage(env, keyId, limit) {
  const day = new Date().toISOString().slice(0, 10)
  const key = `rate:${keyId}:${day}`
  const current = Number((await env.DEVICES.get(key)) ?? 0)
  if (current >= limit) return { exceeded: true, current }
  await env.DEVICES.put(key, String(current + 1), { expirationTtl: 60 * 60 * 26 })
  return { exceeded: false, current: current + 1 }
}

// MARK: - Anthropic

async function callAnthropic(plan, env) {
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': env.ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: plan.model,
      max_tokens: 512,
      system: plan.system,
      output_config: { effort: 'low' },
      messages: plan.messages,
    }),
  })

  if (!response.ok) {
    const detail = await response.text()
    console.warn('anthropic', response.status, detail.slice(0, 500))
    if (response.status === 429) {
      return fail(429, 'rate_limited', 'Gerade zu viele Anfragen. Kurz warten.')
    }
    // Upstream-Details bewusst nicht durchreichen — sie gehören nicht in die App.
    return fail(502, 'upstream', 'Der KI-Dienst ist gerade nicht erreichbar.')
  }

  const data = await response.json()
  if (data.stop_reason === 'refusal') {
    // Nicht 200: Die App wertet nur bei Fehlerstatus den `code` aus.
    return fail(422, 'refused', 'Darauf antworte ich lieber nicht.')
  }

  const text = (data.content ?? [])
    .filter((block) => block.type === 'text')
    .map((block) => block.text)
    .join('')
    .trim()

  if (!text) return fail(502, 'upstream', 'Leere Antwort vom KI-Dienst.')
  return ok({ text })
}
