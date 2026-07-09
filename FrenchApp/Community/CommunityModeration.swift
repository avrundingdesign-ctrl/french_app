import Foundation

// MARK: - Melden (App-Review-Guideline 1.2: User-Generated Content)

/// Grund einer Meldung — landet als `Report`-Record in CloudKit und ist
/// dort im Dashboard einsehbar (zeitnahe Reaktion ist Apple-Pflicht).
enum ReportReason: String, CaseIterable, Identifiable {
    case inappropriate = "Unangemessene Inhalte"
    case harassment = "Belästigung"
    case spam = "Spam oder Werbung"
    case fakeProfile = "Gefälschtes Profil"
    case other = "Anderer Grund"

    var id: String { rawValue }
}

// MARK: - Wortfilter

/// Einfacher On-Device-Filter für anstößige Sprache (DE/FR/EN) —
/// Apple verlangt für Chats eine Filterung anstößiger Inhalte.
/// Geprüft wird pro Wort (keine Teilwort-Treffer), Groß-/Kleinschreibung
/// und Akzente werden ignoriert. Liste bewusst erweiterbar gehalten.
enum ContentFilter {
    private static let blockedWords: Set<String> = [
        // Deutsch
        "arschloch", "fotze", "hurensohn", "wichser", "schlampe",
        "missgeburt", "nutte", "fick", "ficken", "schwuchtel",
        "spast", "neger", "kanake",
        // Französisch (Akzente gefaltet: enculé → encule).
        // „nique" fehlt bewusst: „pique-nique" zerfällt beim Tokenisieren
        // in „pique" + „nique" und wäre sonst ein False Positive.
        "connard", "connasse", "salope", "pute", "encule",
        "ntm", "fdp", "pede", "negro", "bougnoule",
        // Englisch
        "fuck", "bitch", "asshole", "cunt", "nigger", "nigga", "faggot",
    ]

    /// Erstes blockiertes Wort im Text — nil, wenn der Text sauber ist.
    static func firstBlockedWord(in text: String) -> String? {
        let folded = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
        let words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return words.first { blockedWords.contains($0) }
    }

    static func isAcceptable(_ text: String) -> Bool {
        firstBlockedWord(in: text) == nil
    }
}

// MARK: - Gelesen-Status (lokal)

/// Merkt sich pro Match, bis zu welchem Zeitpunkt der Chat gelesen wurde —
/// rein lokal in UserDefaults (kein Server-Roundtrip, keine Lesebestätigung
/// an den Partner). Grundlage für die Ungelesen-Punkte in der Chat-Liste.
struct ChatReadTracker {
    private static let key = "community.lastRead"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastRead(matchID: String) -> Date {
        let stored = defaults.dictionary(forKey: Self.key) as? [String: Date]
        return stored?[matchID] ?? .distantPast
    }

    func markRead(matchID: String, at date: Date) {
        var stored = (defaults.dictionary(forKey: Self.key) as? [String: Date]) ?? [:]
        guard date > (stored[matchID] ?? .distantPast) else { return }
        stored[matchID] = date
        defaults.set(stored, forKey: Self.key)
    }

    func forget(matchID: String) {
        var stored = (defaults.dictionary(forKey: Self.key) as? [String: Date]) ?? [:]
        stored[matchID] = nil
        defaults.set(stored, forKey: Self.key)
    }

    /// Ungelesen, wenn die letzte Nachricht vom Partner stammt und nach dem
    /// letzten Lese-Zeitpunkt eingegangen ist.
    func isUnread(match: TandemMatch, latestMessage: ChatMessage?, viewerID: String) -> Bool {
        guard let latestMessage, latestMessage.senderProfileID != viewerID else { return false }
        return latestMessage.sentAt > lastRead(matchID: match.id)
    }
}
