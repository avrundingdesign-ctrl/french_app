// Prüft die App-Attest-Logik, bei der ein Fehler lautlos wäre: `verify` gibt
// dann einfach `false` zurück, und die App käme nie durch — ohne Hinweis worauf.
//
// Die Attestation (Registrierung) lässt sich hier nicht testen, dafür bräuchte
// es ein echtes, von Apple signiertes Blob. Der Assertion-Pfad läuft dagegen
// bei *jeder* Anfrage — den decken wir vollständig ab.

import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  verifyAssertion,
  derToRawSignature,
  parseAuthenticatorData,
  appIdHash,
  concat,
  sha256,
} from '../src/attest.js'

import { encode as cborEncode } from 'cbor-x'

const TEAM_ID = 'ABCDE12345'
const BUNDLE_ID = 'design.avrunding.frenchapp'

// MARK: - Hilfen

/// Node signiert im rohen P1363-Format, Apple liefert DER. Zum Testen bauen
/// wir also DER nach — genau die Umwandlung, die `derToRawSignature` rückgängig
/// machen muss.
function encodeInteger(bytes) {
  let start = 0
  while (start < bytes.length - 1 && bytes[start] === 0) start += 1
  let value = bytes.slice(start)
  if (value[0] & 0x80) value = Uint8Array.from([0, ...value])
  return Uint8Array.from([0x02, value.length, ...value])
}

function rawToDer(raw) {
  const body = concat(encodeInteger(raw.slice(0, 32)), encodeInteger(raw.slice(32, 64)))
  return concat(Uint8Array.from([0x30, body.length]), body)
}

async function makeDevice() {
  const pair = await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' },
    true,
    ['sign', 'verify']
  )
  const publicKeyRaw = new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey))
  return { pair, publicKeyRaw }
}

async function makeAuthenticatorData({ counter, teamId = TEAM_ID, bundleId = BUNDLE_ID }) {
  const rpIdHash = await appIdHash(teamId, bundleId)
  const tail = new Uint8Array(5)
  tail[0] = 0x40 // Flags — für Assertions ohne Bedeutung
  new DataView(tail.buffer).setUint32(1, counter, false)
  return concat(rpIdHash, tail)
}

async function makeAssertion({ pair, counter, body, teamId, bundleId }) {
  const authData = await makeAuthenticatorData({ counter, teamId, bundleId })
  const signed = concat(authData, await sha256(body))
  const raw = new Uint8Array(
    await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, pair.privateKey, signed)
  )
  return new Uint8Array(
    cborEncode({ signature: rawToDer(raw), authenticatorData: authData })
  )
}

const body = new TextEncoder().encode(JSON.stringify({ mode: 'chat', nonce: 'abc' }))

// MARK: - DER-Umwandlung

test('derToRawSignature liefert 64 Byte und übersteht führende Nullen', async () => {
  const { pair } = await makeDevice()
  // Mehrere Signaturen, damit auch r/s mit führender Null vorkommen.
  for (let i = 0; i < 40; i += 1) {
    const message = new TextEncoder().encode(`nachricht-${i}`)
    const raw = new Uint8Array(
      await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, pair.privateKey, message)
    )
    const roundTripped = derToRawSignature(rawToDer(raw))
    assert.equal(roundTripped.length, 64)
    assert.deepEqual(roundTripped, raw, `Signatur ${i} nicht identisch`)
  }
})

// MARK: - authenticatorData

test('parseAuthenticatorData liest den Zähler big-endian', async () => {
  const authData = await makeAuthenticatorData({ counter: 66051 }) // 0x00010203
  const parsed = parseAuthenticatorData(authData)
  assert.equal(parsed.counter, 66051)
  assert.equal(parsed.rpIdHash.length, 32)
})

test('parseAuthenticatorData weist zu kurze Daten ab', () => {
  assert.throws(() => parseAuthenticatorData(new Uint8Array(10)), /zu kurz/)
})

// MARK: - Assertion

test('gültige Assertion wird angenommen und liefert den neuen Zähler', async () => {
  const { pair, publicKeyRaw } = await makeDevice()
  const assertion = await makeAssertion({ pair, counter: 7, body })

  const result = await verifyAssertion({
    assertion,
    publicKeyRaw,
    storedCounter: 6,
    body,
    teamId: TEAM_ID,
    bundleId: BUNDLE_ID,
  })
  assert.equal(result.counter, 7)
})

test('verändeter Body wird abgewiesen', async () => {
  const { pair, publicKeyRaw } = await makeDevice()
  const assertion = await makeAssertion({ pair, counter: 1, body })
  const tampered = new TextEncoder().encode(JSON.stringify({ mode: 'chat', nonce: 'xyz' }))

  await assert.rejects(
    verifyAssertion({
      assertion,
      publicKeyRaw,
      storedCounter: 0,
      body: tampered,
      teamId: TEAM_ID,
      bundleId: BUNDLE_ID,
    }),
    /Signatur ungültig/
  )
})

test('wiedereingespielte Anfrage wird abgewiesen (Zähler nicht gestiegen)', async () => {
  const { pair, publicKeyRaw } = await makeDevice()
  const assertion = await makeAssertion({ pair, counter: 5, body })

  await assert.rejects(
    verifyAssertion({
      assertion,
      publicKeyRaw,
      storedCounter: 5,
      body,
      teamId: TEAM_ID,
      bundleId: BUNDLE_ID,
    }),
    /Wiedereinspielung/
  )
})

test('Assertion einer fremden App wird abgewiesen', async () => {
  const { pair, publicKeyRaw } = await makeDevice()
  const assertion = await makeAssertion({
    pair,
    counter: 1,
    body,
    teamId: TEAM_ID,
    bundleId: 'com.fremde.app',
  })

  await assert.rejects(
    verifyAssertion({
      assertion,
      publicKeyRaw,
      storedCounter: 0,
      body,
      teamId: TEAM_ID,
      bundleId: BUNDLE_ID,
    }),
    /anderen App/
  )
})

test('Signatur eines anderen Geräts wird abgewiesen', async () => {
  const { pair } = await makeDevice()
  const other = await makeDevice()
  const assertion = await makeAssertion({ pair, counter: 1, body })

  await assert.rejects(
    verifyAssertion({
      assertion,
      publicKeyRaw: other.publicKeyRaw,
      storedCounter: 0,
      body,
      teamId: TEAM_ID,
      bundleId: BUNDLE_ID,
    }),
    /Signatur ungültig/
  )
})
