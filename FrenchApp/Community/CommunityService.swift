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

    @discardableResult
    func send(
        text: String,
        language: TandemLanguage,
        in match: TandemMatch,
        from profile: CommunityProfile
    ) async throws -> ChatMessage
}
