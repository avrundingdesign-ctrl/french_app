import Foundation

/// Verlauf des KI-Chats, lokal als JSON in Application Support.
///
/// Bewusst weder SwiftData noch CloudKit: Der Community-Bereich ist heute
/// komplett SwiftData-frei, und ein neues `@Model` würde eine Schema-Migration
/// des bestehenden `ModelContainer` auslösen — unnötiges Risiko für einen rein
/// lokalen Chatverlauf. CloudKit scheidet aus, weil der Verlauf niemanden
/// außer dem Gerät etwas angeht.
actor AIChatStore {
    /// Obergrenze der abgelegten Nachrichten, damit die Datei nicht unbegrenzt
    /// wächst. Deutlich über `ClaudeAIPartnerService.historyLimit` — der Nutzer
    /// darf weiter zurückscrollen, als die KI sich erinnert.
    static let storageLimit = 200

    private let url: URL
    private var cached: [ChatMessage]?

    init(filename: String = "ai-chat.json") {
        let manager = FileManager.default
        let directory = (try? manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? manager.temporaryDirectory
        self.url = directory.appendingPathComponent(filename)
    }

    func load() -> [ChatMessage] {
        if let cached { return cached }
        guard
            let data = try? Data(contentsOf: url),
            let messages = try? JSONDecoder().decode([ChatMessage].self, from: data)
        else {
            cached = []
            return []
        }
        cached = messages
        return messages
    }

    @discardableResult
    func append(_ message: ChatMessage) -> [ChatMessage] {
        var messages = load()
        messages.append(message)
        return persist(messages)
    }

    @discardableResult
    func reset() -> [ChatMessage] {
        persist([])
    }

    @discardableResult
    private func persist(_ messages: [ChatMessage]) -> [ChatMessage] {
        let trimmed = Array(messages.suffix(Self.storageLimit))
        cached = trimmed
        if let data = try? JSONEncoder().encode(trimmed) {
            try? data.write(to: url, options: .atomic)
        }
        return trimmed
    }
}
