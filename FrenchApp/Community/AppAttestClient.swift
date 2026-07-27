import Foundation
import CryptoKit
#if canImport(DeviceCheck)
import DeviceCheck
#endif

/// App Attest: weist dem Proxy nach, dass eine Anfrage aus einer echten,
/// unveränderten Instanz dieser App auf einem echten Apple-Gerät stammt.
///
/// Das ist der eigentliche Schutz des Proxys. Der private Schlüssel entsteht in
/// der Secure Enclave und verlässt sie nie — die App kennt nur eine `keyID`.
/// Wer die Proxy-Adresse aus dem Binary liest, kann sie deshalb trotzdem nicht
/// benutzen. Genau darum darf der Anthropic-Key auf dem Server liegen.
///
/// Ablauf:
/// 1. **Einmalig:** Schlüssel erzeugen → Challenge vom Server holen →
///    `attestKey` → Server prüft Attestation und merkt sich den Public Key.
/// 2. **Pro Anfrage:** `generateAssertion` über den Hash des Request-Bodys.
///    Der Server prüft die Signatur und dass der Zähler gestiegen ist — das
///    verhindert Wiedereinspielen alter Anfragen ohne zusätzlichen Roundtrip.
///
/// - Important: Auf dem **Simulator** ist App Attest nicht verfügbar
///   (`isSupported == false`). Zum Testen dort den eigenen API-Key hinterlegen
///   oder den Demo-Modus nutzen.
actor AppAttestClient {

    enum AttestError: LocalizedError, Equatable {
        case unsupported
        case registrationFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return "Dieses Gerät unterstützt die gesicherte Verbindung nicht (im Simulator normal)."
            case .registrationFailed(let message):
                return message
            }
        }
    }

    private let baseURL: URL
    private let session: URLSession
    private let defaults: UserDefaults

    private static let keyIDStorageKey = "ai.attest.keyID"
    private static let registeredStorageKey = "ai.attest.registered"

    /// Läuft eine Registrierung, hängen sich weitere Aufrufer daran. Actors
    /// sind über `await` reentrant: Ohne das würden zwei parallele Anfragen
    /// (Chat und Übersetzung) je einen Schlüssel erzeugen, der zweite den
    /// ersten in den Defaults überschreiben — und der Server kennte den
    /// Schlüssel nicht mehr, mit dem danach signiert wird.
    private var registration: Task<String, Error>?

    init(
        baseURL: URL,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.baseURL = baseURL
        self.session = session
        self.defaults = defaults
    }

    static var isSupported: Bool {
        #if canImport(DeviceCheck)
        return DCAppAttestService.shared.isSupported
        #else
        return false
        #endif
    }

    /// Signiert den Request-Body und liefert die Header für den Proxy.
    func headers(for body: Data) async throws -> [String: String] {
        #if canImport(DeviceCheck)
        guard DCAppAttestService.shared.isSupported else { throw AttestError.unsupported }

        let keyID = try await registeredKeyID()
        let hash = Data(SHA256.hash(data: body))
        let assertion = try await DCAppAttestService.shared.generateAssertion(
            keyID,
            clientDataHash: hash
        )
        return [
            "x-attest-key-id": keyID,
            "x-attest-assertion": assertion.base64EncodedString(),
        ]
        #else
        throw AttestError.unsupported
        #endif
    }

    /// Setzt die Registrierung zurück — nötig, wenn der Server den Schlüssel
    /// nicht mehr kennt (z. B. nach einem Datenverlust auf Serverseite).
    func resetRegistration() {
        defaults.removeObject(forKey: Self.keyIDStorageKey)
        defaults.removeObject(forKey: Self.registeredStorageKey)
    }

    // MARK: - Registrierung

    #if canImport(DeviceCheck)
    private func registeredKeyID() async throws -> String {
        if let existing = defaults.string(forKey: Self.keyIDStorageKey),
           defaults.bool(forKey: Self.registeredStorageKey) {
            return existing
        }

        // Läuft schon eine Registrierung, deren Ergebnis abwarten statt eine
        // zweite zu starten.
        if let registration {
            return try await registration.value
        }

        let task = Task { try await performRegistration() }
        registration = task
        defer { registration = nil }
        return try await task.value
    }

    private func performRegistration() async throws -> String {
        // Ein bereits erzeugter, aber nicht registrierter Schlüssel wird
        // wiederverwendet — `generateKey` ist nicht kostenlos.
        let keyID: String
        if let existing = defaults.string(forKey: Self.keyIDStorageKey) {
            keyID = existing
        } else {
            keyID = try await DCAppAttestService.shared.generateKey()
            defaults.set(keyID, forKey: Self.keyIDStorageKey)
        }

        let challenge = try await fetchChallenge()
        let attestation = try await DCAppAttestService.shared.attestKey(
            keyID,
            clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8)))
        )
        try await register(keyID: keyID, attestation: attestation, challenge: challenge)

        defaults.set(true, forKey: Self.registeredStorageKey)
        return keyID
    }

    private func fetchChallenge() async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/attest/challenge"))
        request.httpMethod = "GET"
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AttestError.registrationFailed("Der Server hat keine Challenge geliefert.")
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let challenge = json["challenge"] as? String
        else {
            throw AttestError.registrationFailed("Unerwartete Antwort bei der Anmeldung.")
        }
        return challenge
    }

    private func register(keyID: String, attestation: Data, challenge: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/attest/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(keyID, forHTTPHeaderField: "x-attest-key-id")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "attestation": attestation.base64EncodedString(),
            "challenge": challenge,
        ])

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            // Registrierung fehlgeschlagen → Schlüssel verwerfen, damit der
            // nächste Versuch sauber neu anfängt.
            defaults.removeObject(forKey: Self.keyIDStorageKey)
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String }
            throw AttestError.registrationFailed(
                detail ?? "Die App konnte sich nicht am Server anmelden."
            )
        }
    }
    #endif
}
