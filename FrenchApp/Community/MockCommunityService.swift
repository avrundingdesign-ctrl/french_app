import Foundation

/// Demo-Backend: In-Memory-Store mit simulierten französischen Tandem-Partnern.
/// Aktiv, solange kein iCloud-Konto verfügbar ist (oder per Launch-Argument
/// `--community-demo`). Antworten der Demo-Partner kommen automatisch.
actor MockCommunityService: CommunityService {
    private var myProfile: CommunityProfile?
    private var others: [CommunityProfile]
    private var matchList: [TandemMatch] = []
    private var messageList: [ChatMessage] = []
    private var blocks: [(blockerID: String, blockedID: String)] = []
    private(set) var reports: [(profileID: String, reason: ReportReason, details: String)] = []

    init() {
        others = [
            CommunityProfile(
                id: "demo_camille",
                displayName: "Camille",
                bio: "Salut ! Je suis de Lyon et j'apprends l'allemand pour mes études. J'adore cuisiner et parler de tout !",
                hobbies: ["Kochen", "Wandern", "Kino"],
                nativeLanguage: .french,
                photoData: nil,
                createdAt: .now.addingTimeInterval(-86400 * 12)
            ),
            CommunityProfile(
                id: "demo_theo",
                displayName: "Théo",
                bio: "Bonjour ! Musicien de Toulouse. Je veux améliorer mon allemand — on s'écrit ?",
                hobbies: ["Musik", "Gitarre", "Fußball"],
                nativeLanguage: .french,
                photoData: nil,
                createdAt: .now.addingTimeInterval(-86400 * 5)
            ),
            CommunityProfile(
                id: "demo_ines",
                displayName: "Inès",
                bio: "Coucou ! Prof de yoga à Bordeaux. L'allemand me fascine depuis toujours.",
                hobbies: ["Yoga", "Lesen", "Reisen"],
                nativeLanguage: .french,
                photoData: nil,
                createdAt: .now.addingTimeInterval(-86400 * 2)
            ),
            CommunityProfile(
                id: "demo_lena",
                displayName: "Lena",
                bio: "Hallo! Ich komme aus Hamburg und liebe die französische Küste.",
                hobbies: ["Segeln", "Fotografie"],
                nativeLanguage: .german,
                photoData: nil,
                createdAt: .now.addingTimeInterval(-86400 * 8)
            ),
        ]
    }

    func accountAvailable() async -> Bool { true }

    func loadMyProfile() async throws -> CommunityProfile? { myProfile }

    func saveProfile(_ draft: ProfileDraft) async throws -> CommunityProfile {
        let profile = CommunityProfile(
            id: myProfile?.id ?? "demo_me",
            displayName: draft.displayName.trimmingCharacters(in: .whitespaces),
            bio: draft.bio,
            hobbies: draft.hobbies,
            nativeLanguage: draft.nativeLanguage,
            photoData: draft.photoData,
            createdAt: myProfile?.createdAt ?? .now
        )
        myProfile = profile
        return profile
    }

    func candidates(for profile: CommunityProfile) async throws -> [CommunityProfile] {
        let matched = Set(matchList.filter { $0.involves(profile.id) }.map { $0.otherProfileID(for: profile.id) })
        let blocked = try await blockedProfileIDs(for: profile)
        return others.filter {
            $0.nativeLanguage == profile.learningLanguage
                && !matched.contains($0.id)
                && !blocked.contains($0.id)
        }
    }

    func profiles(ids: [String]) async throws -> [String: CommunityProfile] {
        var result: [String: CommunityProfile] = [:]
        for other in others where ids.contains(other.id) {
            result[other.id] = other
        }
        if let mine = myProfile, ids.contains(mine.id) {
            result[mine.id] = mine
        }
        return result
    }

    func requestMatch(from me: CommunityProfile, to partner: CommunityProfile) async throws -> TandemMatch {
        // Demo-Partner nehmen sofort an — so lässt sich der Chat direkt testen.
        let match = TandemMatch(
            id: UUID().uuidString,
            requesterID: me.id,
            partnerID: partner.id,
            status: .accepted,
            createdAt: .now
        )
        matchList.append(match)
        let greeting = partner.learningLanguage == .german
            ? "Hallo! Danke für deine Anfrage — ich freue mich, mit dir zu üben. Lernst du schon lange Französisch?"
            : "Salut ! Merci pour ta demande — je suis ravi de pratiquer avec toi. Tu apprends l'allemand depuis longtemps ?"
        // Jeder schreibt in seiner Lernsprache: der französische Partner auf Deutsch.
        messageList.append(ChatMessage(
            id: UUID().uuidString,
            matchID: match.id,
            senderProfileID: partner.id,
            text: greeting,
            language: partner.learningLanguage,
            sentAt: .now
        ))
        return match
    }

    func matches(for profile: CommunityProfile) async throws -> [TandemMatch] {
        matchList.filter { $0.involves(profile.id) }.sorted { $0.createdAt > $1.createdAt }
    }

    func accept(_ match: TandemMatch) async throws -> TandemMatch {
        guard let index = matchList.firstIndex(where: { $0.id == match.id }) else { return match }
        matchList[index].status = .accepted
        return matchList[index]
    }

    func messages(for match: TandemMatch) async throws -> [ChatMessage] {
        messageList.filter { $0.matchID == match.id }.sorted { $0.sentAt < $1.sentAt }
    }

    func latestMessage(for match: TandemMatch) async throws -> ChatMessage? {
        try await messages(for: match).last
    }

    func send(
        text: String,
        language: TandemLanguage,
        in match: TandemMatch,
        from profile: CommunityProfile
    ) async throws -> ChatMessage {
        let message = ChatMessage(
            id: UUID().uuidString,
            matchID: match.id,
            senderProfileID: profile.id,
            text: text,
            language: language,
            sentAt: .now
        )
        messageList.append(message)
        scheduleDemoReply(in: match, to: profile)
        return message
    }

    /// Simulierte Antwort des Demo-Partners nach kurzer Verzögerung.
    private func scheduleDemoReply(in match: TandemMatch, to me: CommunityProfile) {
        let partnerID = match.otherProfileID(for: me.id)
        guard let partner = others.first(where: { $0.id == partnerID }) else { return }
        let replies = partner.learningLanguage == .german
            ? [
                "Das klingt super! Erzähl mir mehr davon.",
                "Interessant! Wie sagt man das auf Französisch?",
                "Ich verstehe. Bei mir ist es ähnlich!",
                "Haha, sehr gut! Dein Französisch wird immer besser.",
            ]
            : [
                "C'est génial ! Raconte-moi plus.",
                "Très intéressant ! Et toi, qu'est-ce que tu en penses ?",
                "Je comprends. Chez moi, c'est pareil !",
            ]
        let reply = ChatMessage(
            id: UUID().uuidString,
            matchID: match.id,
            senderProfileID: partner.id,
            text: replies.randomElement() ?? "D'accord !",
            language: partner.learningLanguage,
            sentAt: .now.addingTimeInterval(2)
        )
        Task {
            try? await Task.sleep(for: .seconds(2))
            await self.append(reply)
        }
    }

    private func append(_ message: ChatMessage) {
        messageList.append(message)
    }

    // MARK: - Moderation

    func blockedProfileIDs(for profile: CommunityProfile) async throws -> Set<String> {
        var ids: Set<String> = []
        for block in blocks {
            if block.blockerID == profile.id { ids.insert(block.blockedID) }
            if block.blockedID == profile.id { ids.insert(block.blockerID) }
        }
        return ids
    }

    func block(profileID: String, by profile: CommunityProfile) async throws {
        blocks.append((blockerID: profile.id, blockedID: profileID))
        for match in matchList where match.involves(profile.id) && match.involves(profileID) {
            try await endMatch(match)
        }
    }

    func unblock(profileID: String, by profile: CommunityProfile) async throws {
        blocks.removeAll { $0.blockerID == profile.id && $0.blockedID == profileID }
    }

    func report(
        profileID: String,
        matchID: String?,
        reason: ReportReason,
        details: String,
        by profile: CommunityProfile
    ) async throws {
        reports.append((profileID: profileID, reason: reason, details: details))
    }

    func endMatch(_ match: TandemMatch) async throws {
        matchList.removeAll { $0.id == match.id }
        messageList.removeAll { $0.matchID == match.id }
    }

    func deleteMyProfile(_ profile: CommunityProfile) async throws {
        for match in matchList where match.involves(profile.id) {
            try await endMatch(match)
        }
        blocks.removeAll { $0.blockerID == profile.id }
        myProfile = nil
    }
}
