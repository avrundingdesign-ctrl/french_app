import Foundation
import Security

/// Ablage des Anthropic-API-Keys.
///
/// Bewusst nicht in `UserDefaults`: Der Key ist ein Zugangsgeheimnis mit
/// direkter Kostenwirkung. Hinter dem Protokoll gekapselt, damit später ein
/// fest eingebauter Key oder ein eigener Proxy-Server dazukommen kann, ohne
/// den KI-Chat selbst anzufassen.
protocol AIKeyStoring: Sendable {
    func load() -> String?
    @discardableResult func save(_ key: String) -> Bool
    @discardableResult func clear() -> Bool
}

extension AIKeyStoring {
    var hasKey: Bool { load() != nil }
}

/// Produktivablage im Keychain.
struct KeychainAIKeyStore: AIKeyStoring {
    private let service: String
    private let account: String

    init(
        service: String = "design.avrunding.frenchapp.ai",
        account: String = "anthropic.apiKey"
    ) {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)
        else { return nil }

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Legt den Key an oder überschreibt ihn; ein leerer String löscht ihn.
    @discardableResult
    func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return clear() }
        guard let data = trimmed.data(using: .utf8) else { return false }

        // `afterFirstUnlock`: Der Chat soll nach einem Geräteneustart ohne
        // erneute Eingabe funktionieren, sobald einmal entsperrt wurde.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var insert = baseQuery
        insert.merge(attributes) { current, _ in current }
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func clear() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// Ersatz ohne Keychain-Zugriff — für Tests und den Demo-Modus.
final class InMemoryAIKeyStore: AIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?

    init(key: String? = nil) {
        self.key = key
    }

    func load() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let key, !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        self.key = trimmed.isEmpty ? nil : trimmed
        return true
    }

    @discardableResult
    func clear() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        key = nil
        return true
    }
}
