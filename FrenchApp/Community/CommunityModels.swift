import Foundation

// MARK: - Tandem-Community (v2 Online)

/// Die beiden Sprachseiten des Tandems. Jedes Profil hat eine Muttersprache —
/// gesucht wird immer die Gegenseite (Deutsch ↔ Französisch).
enum TandemLanguage: String, Codable, CaseIterable, Identifiable {
    case german = "de"
    case french = "fr"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .german: return "Deutsch"
        case .french: return "Französisch"
        }
    }

    var flag: String {
        switch self {
        case .german: return "🇩🇪"
        case .french: return "🇫🇷"
        }
    }

    /// Die jeweils andere Sprache — Muttersprache des Wunschpartners.
    var other: TandemLanguage {
        self == .german ? .french : .german
    }

    var localeIdentifier: String {
        switch self {
        case .german: return "de-DE"
        case .french: return "fr-FR"
        }
    }
}

/// Öffentliches Nutzerprofil. `id` ist der CloudKit-Record-Name
/// (bzw. eine Mock-ID im Demo-Modus) — pro iCloud-Account genau ein Profil.
struct CommunityProfile: Identifiable, Equatable {
    var id: String
    var displayName: String
    var bio: String
    var hobbies: [String]
    var nativeLanguage: TandemLanguage
    var photoData: Data?
    var createdAt: Date

    /// Die Sprache, die dieses Profil lernt und im Chat liest & schreibt.
    var learningLanguage: TandemLanguage { nativeLanguage.other }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

/// Entwurf beim Anlegen/Bearbeiten des Profils.
struct ProfileDraft {
    var displayName = ""
    var bio = ""
    var hobbies: [String] = []
    var nativeLanguage: TandemLanguage = .german
    var photoData: Data?

    init() {}

    init(profile: CommunityProfile) {
        displayName = profile.displayName
        bio = profile.bio
        hobbies = profile.hobbies
        nativeLanguage = profile.nativeLanguage
        photoData = profile.photoData
    }

    var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

enum MatchStatus: String {
    case pending
    case accepted
}

/// Tandem-Paar: entsteht als Anfrage (`pending`) und wird vom Gegenüber
/// angenommen (`accepted`) — erst dann ist der Chat offen.
struct TandemMatch: Identifiable, Equatable {
    var id: String
    var requesterID: String
    var partnerID: String
    var status: MatchStatus
    var createdAt: Date

    func otherProfileID(for profileID: String) -> String {
        requesterID == profileID ? partnerID : requesterID
    }

    /// Eingehende, noch unbeantwortete Anfrage an dieses Profil?
    func isIncoming(for profileID: String) -> Bool {
        partnerID == profileID && status == .pending
    }

    func involves(_ profileID: String) -> Bool {
        requesterID == profileID || partnerID == profileID
    }
}

/// Chat-Nachricht. `language` ist die Sprache, in der der Absender
/// geschrieben hat (immer seine Lernsprache) — die Gegenseite bekommt
/// den Text on-device in ihre Lernsprache übersetzt.
struct ChatMessage: Identifiable, Equatable {
    var id: String
    var matchID: String
    var senderProfileID: String
    var text: String
    var language: TandemLanguage
    var sentAt: Date
}

// MARK: - Anzeige-Regeln

enum ChatDisplay {
    /// Der Betrachter liest den Chat in seiner Lernsprache. Übersetzt werden
    /// muss alles, was nicht schon in dieser Sprache geschrieben wurde —
    /// also die Nachrichten des Partners (der in der Gegensprache übt).
    static func needsTranslation(_ message: ChatMessage, for viewer: CommunityProfile) -> Bool {
        message.language != viewer.learningLanguage
    }

    /// Übersetzungsrichtung aus Sicht des Betrachters: von seiner
    /// Muttersprache (= Schreibsprache des Partners) in seine Lernsprache.
    static func translationDirection(for viewer: CommunityProfile) -> (source: TandemLanguage, target: TandemLanguage) {
        (viewer.nativeLanguage, viewer.learningLanguage)
    }
}
