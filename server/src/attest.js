// Apple App Attest — Prüfung auf Serverseite.
//
// Zwei Vorgänge:
//   Registrierung (einmal pro Installation): Die Attestation beweist, dass der
//     Schlüssel in der Secure Enclave eines echten Apple-Geräts entstanden ist
//     und zu genau dieser App gehört. Wir merken uns den Public Key.
//   Assertion (pro Anfrage): Signatur über den Request-Body, plus ein Zähler,
//     der monoton steigen muss — das verhindert Wiedereinspielen alter
//     Anfragen, ohne dass die App vorher eine Challenge holen muss.
//
// Ohne diese Prüfung wäre der Proxy ein offener, kostenloser Claude-Zugang für
// jeden, der die Adresse aus dem App-Binary liest.

import { decode as cborDecode } from 'cbor-x'
import * as x509 from '@peculiar/x509'

/// Apple App Attest Root CA (öffentlich, aus Apples Dokumentation).
const APPLE_ROOT_CA_PEM = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEA3YsaNIGn+9O8J5SM6byMcCsIfsjt0z+K2K/Q
qYirprLwCmLzUx8dtd7bLZlpDGDf
-----END CERTIFICATE-----`

/// OID, unter dem Apple den Nonce ins Zertifikat legt.
const NONCE_OID = '1.2.840.113635.100.8.2'

// MARK: - Hilfen

export function b64ToBytes(value) {
  const binary = atob(value)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i)
  return bytes
}

export function bytesToB64(bytes) {
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary)
}

export function concat(...parts) {
  const total = parts.reduce((sum, part) => sum + part.length, 0)
  const result = new Uint8Array(total)
  let offset = 0
  for (const part of parts) {
    result.set(part, offset)
    offset += part.length
  }
  return result
}

export async function sha256(bytes) {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i += 1) diff |= a[i] ^ b[i]
  return diff === 0
}

/// WebCrypto erwartet ECDSA-Signaturen als rohes r‖s (P1363), Apple liefert
/// sie DER-kodiert. Ohne diese Umwandlung schlägt jede Prüfung fehl — und
/// zwar lautlos, weil `verify` einfach `false` zurückgibt.
export function derToRawSignature(der) {
  let offset = 0
  if (der[offset] !== 0x30) throw new Error('Signatur: SEQUENCE erwartet')
  offset += 1
  // Länge überspringen (kurze oder lange Form).
  if (der[offset] & 0x80) offset += 1 + (der[offset] & 0x7f)
  else offset += 1

  const readInt = () => {
    if (der[offset] !== 0x02) throw new Error('Signatur: INTEGER erwartet')
    offset += 1
    const length = der[offset]
    offset += 1
    let value = der.slice(offset, offset + length)
    offset += length
    // Führende Null (Vorzeichenbit) entfernen, links auf 32 Byte auffüllen.
    while (value.length > 32 && value[0] === 0x00) value = value.slice(1)
    if (value.length > 32) throw new Error('Signatur: Wert zu lang')
    const padded = new Uint8Array(32)
    padded.set(value, 32 - value.length)
    return padded
  }

  const r = readInt()
  const s = readInt()
  return concat(r, s)
}

/// `authenticatorData` nach Apples/WebAuthn-Aufbau:
/// 32 Byte rpIdHash ‖ 1 Byte Flags ‖ 4 Byte Zähler (big endian) ‖ Rest.
export function parseAuthenticatorData(authData) {
  if (authData.length < 37) throw new Error('authenticatorData zu kurz')
  const view = new DataView(authData.buffer, authData.byteOffset, authData.byteLength)
  return {
    rpIdHash: authData.slice(0, 32),
    flags: authData[32],
    counter: view.getUint32(33, false),
    rest: authData.slice(37),
  }
}

/// SHA256("<TeamID>.<BundleID>") — muss dem rpIdHash entsprechen.
export async function appIdHash(teamId, bundleId) {
  return sha256(new TextEncoder().encode(`${teamId}.${bundleId}`))
}

async function importPublicKey(rawPoint) {
  return crypto.subtle.importKey(
    'raw',
    rawPoint,
    { name: 'ECDSA', namedCurve: 'P-256' },
    true,
    ['verify']
  )
}

// MARK: - Registrierung

/**
 * Prüft die Attestation und liefert den Public Key zum Merken.
 *
 * @returns {Promise<{publicKeyRaw: Uint8Array, counter: number}>}
 */
export async function verifyAttestation({
  attestation,
  keyId,
  challenge,
  teamId,
  bundleId,
  allowDevelopmentEnvironment = false,
}) {
  const decoded = cborDecode(attestation)
  if (decoded?.fmt !== 'apple-appattest') throw new Error('Unbekanntes Attestation-Format')

  const x5c = decoded.attStmt?.x5c
  if (!Array.isArray(x5c) || x5c.length < 2) throw new Error('Zertifikatskette fehlt')

  const credCert = new x509.X509Certificate(new Uint8Array(x5c[0]))
  const caCert = new x509.X509Certificate(new Uint8Array(x5c[1]))
  const rootCert = new x509.X509Certificate(APPLE_ROOT_CA_PEM)

  // 1. Kette bis zu Apples Root prüfen.
  if (!(await caCert.verify({ publicKey: await rootCert.publicKey.export() }))) {
    throw new Error('CA-Zertifikat stammt nicht von Apple')
  }
  if (!(await credCert.verify({ publicKey: await caCert.publicKey.export() }))) {
    throw new Error('Gerätezertifikat stammt nicht von Apples CA')
  }

  const authData = new Uint8Array(decoded.authData)
  const clientDataHash = await sha256(new TextEncoder().encode(challenge))

  // 2. Nonce: SHA256(authData ‖ clientDataHash) muss im Zertifikat stehen.
  const expectedNonce = await sha256(concat(authData, clientDataHash))
  const extension = credCert.getExtension(NONCE_OID)
  if (!extension) throw new Error('Nonce-Erweiterung fehlt im Zertifikat')
  const extensionBytes = new Uint8Array(extension.value)
  // Aufbau: SEQUENCE { [1] { OCTET STRING (32 Byte) } } — der Nonce steht am Ende.
  const embeddedNonce = extensionBytes.slice(extensionBytes.length - 32)
  if (!timingSafeEqual(embeddedNonce, expectedNonce)) {
    throw new Error('Nonce stimmt nicht — Challenge veraltet oder manipuliert')
  }

  // 3. keyId muss der SHA256 des Public Key sein.
  const publicKeyRaw = new Uint8Array(await credCert.publicKey.export().then((k) =>
    crypto.subtle.exportKey('raw', k)
  ))
  const publicKeyHash = await sha256(publicKeyRaw)
  if (!timingSafeEqual(publicKeyHash, b64ToBytes(keyId))) {
    throw new Error('keyId passt nicht zum Zertifikat')
  }

  // 4. App-Bindung und Zählerstand.
  const parsed = parseAuthenticatorData(authData)
  if (!timingSafeEqual(parsed.rpIdHash, await appIdHash(teamId, bundleId))) {
    throw new Error('Attestation gehört zu einer anderen App')
  }
  if (parsed.counter !== 0) throw new Error('Zähler bei der Registrierung muss 0 sein')

  // 5. Umgebung: In Produktion darf kein Development-Attest durchkommen.
  const aaguid = new TextDecoder().decode(parsed.rest.slice(0, 16)).replace(/\0+$/, '')
  if (aaguid === 'appattestdevelop' && !allowDevelopmentEnvironment) {
    throw new Error('Development-Attestation in der Produktivumgebung')
  }
  if (aaguid !== 'appattestdevelop' && aaguid !== 'appattest') {
    throw new Error(`Unerwartete Attestation-Umgebung: ${aaguid}`)
  }

  return { publicKeyRaw, counter: parsed.counter }
}

// MARK: - Pro Anfrage

/**
 * Prüft die Assertion über den Request-Body.
 *
 * @returns {Promise<{counter: number}>} neuer Zählerstand zum Speichern
 */
export async function verifyAssertion({
  assertion,
  publicKeyRaw,
  storedCounter,
  body,
  teamId,
  bundleId,
}) {
  const decoded = cborDecode(assertion)
  const signature = new Uint8Array(decoded.signature)
  const authData = new Uint8Array(decoded.authenticatorData)

  const parsed = parseAuthenticatorData(authData)
  if (!timingSafeEqual(parsed.rpIdHash, await appIdHash(teamId, bundleId))) {
    throw new Error('Assertion gehört zu einer anderen App')
  }
  // Streng größer: Gleicher Zähler heißt wiedereingespielte Anfrage.
  if (parsed.counter <= storedCounter) {
    throw new Error('Zähler ist nicht gestiegen — Wiedereinspielung')
  }

  const clientDataHash = await sha256(body)
  const signedData = concat(authData, clientDataHash)

  const key = await importPublicKey(publicKeyRaw)
  const valid = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    derToRawSignature(signature),
    signedData
  )
  if (!valid) throw new Error('Signatur ungültig')

  return { counter: parsed.counter }
}
