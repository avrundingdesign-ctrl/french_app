import Foundation

// MARK: - Backend-Schnittstelle

enum CommunityError: LocalizedError {
    case noAccount
    case profileMissing
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noAccount:
            return "Kein iCloud-Konto gefunden. Melde dich in den Einstellungen bei iCloud an."
        case .profileMissing:
            return "Lege zuerst dein Profil an."
        case .network(let message):
            return message
        }
    }
}

/// Backend der Tandem-Community. Produktiv steht dahinter CloudKit
/// (Login über die Apple-ID, keine Passwörter); der Demo-Modus nutzt
/// einen In-Memory-Store mit simulierten Partnern.
protocol CommunityService {
    /// Ist ein Konto verfügbar (iCloud angemeldet)?
    func accountAvailable() async -> Bool

    /// Eigenes Profil laden — nil, wenn noch keins angelegt wurde.
    func loadMyProfile() async throws -> CommunityProfile?

    /// Profil anlegen oder aktualisieren.
    @discardableResult
    func saveProfile(_ draft: ProfileDraft) async throws -> CommunityProfile

    /// Partnervorschläge: Profile mit der jeweils anderen Muttersprache,
    /// ohne bereits bestehende Matches.
    func candidates(for profile: CommunityProfile) async throws -> [CommunityProfile]

    /// Profile zu IDs auflösen (für Match-Listen).
    func profiles(ids: [String]) async throws -> [String: CommunityProfile]

    @discardableResult
    func requestMatch(from me: CommunityProfile, to partner: CommunityProfile) async throws -> TandemMatch

    /// Alle Matches (Anfragen + angenommene), an denen das Profil beteiligt ist.
    func matches(for profile: CommunityProfile) async throws -> [TandemMatch]

    @discardableResult
    func accept(_ match: TandemMatch) async throws -> TandemMatch

    func messages(for match: TandemMatch) async throws -> [ChatMessage]

    /// Neueste Nachricht eines Matches — für Vorschau und Ungelesen-Status
    /// in der Chat-Liste.
    func latestMessage(for match: TandemMatch) async throws -> ChatMessage?

    @discardableResult
    func send(
        text: String,
        language: TandemLanguage,
        in match: TandemMatch,
        from profile: CommunityProfile
    ) async throws -> ChatMessage

    // MARK: Moderation (App-Review-Guideline 1.2)

    /// IDs aller Profile, die dieses Profil blockiert hat oder von denen es
    /// blockiert wurde — beide Richtungen verschwinden aus den Vorschlägen.
    func blockedProfileIDs(for profile: CommunityProfile) async throws -> Set<String>

    /// Blockiert ein Profil und löst ein gemeinsames Match samt Verlauf auf.
    func block(profileID: String, by profile: CommunityProfile) async throws

    func unblock(profileID: String, by profile: CommunityProfile) async throws

    /// Meldet ein Profil (optional mit Match-Bezug) — landet als Report
    /// beim Betreiber, nicht beim gemeldeten Nutzer.
    func report(
        profileID: String,
        matchID: String?,
        reason: ReportReason,
        details: String,
        by profile: CommunityProfile
    ) async throws

    /// Beendet ein Tandem: Match und kompletter Nachrichtenverlauf werden
    /// für beide Seiten gelöscht.
    func endMatch(_ match: TandemMatch) async throws

    /// Löscht das eigene Profil vollständig (Guideline 5.1.1(v)):
    /// Profil, alle eigenen Matches samt Verläufen und Block-Einträge.
    func deleteMyProfile(_ profile: CommunityProfile) async throws
}
