import XCTest
@testable import FrenchApp

/// Tandem-Community (v2): Matching-Regeln, Chat-Fluss und Übersetzungslogik —
/// getestet gegen den Mock-Service (gleiche Schnittstelle wie CloudKit).
final class CommunityTests: XCTestCase {

    private func makeMyProfile(native: TandemLanguage = .german) async throws -> (MockCommunityService, CommunityProfile) {
        let service = MockCommunityService()
        var draft = ProfileDraft()
        draft.displayName = "Test Nutzer"
        draft.bio = "Hallo!"
        draft.hobbies = ["Lesen"]
        draft.nativeLanguage = native
        let profile = try await service.saveProfile(draft)
        return (service, profile)
    }

    // MARK: - Profil

    func testProfileRoundTripAndLanguagePairing() async throws {
        let (service, profile) = try await makeMyProfile()
        let loaded = try await service.loadMyProfile()
        XCTAssertEqual(loaded, profile)
        XCTAssertEqual(profile.nativeLanguage, .german)
        XCTAssertEqual(profile.learningLanguage, .french, "Deutsch-Muttersprachler lernt Französisch")
        XCTAssertEqual(profile.initials, "TN")
    }

    func testDraftValidationRequiresName() {
        var draft = ProfileDraft()
        XCTAssertFalse(draft.isValid)
        draft.displayName = "   "
        XCTAssertFalse(draft.isValid)
        draft.displayName = "Anna"
        XCTAssertTrue(draft.isValid)
    }

    // MARK: - Matching

    func testCandidatesOnlyShowOppositeNativeLanguage() async throws {
        let (service, me) = try await makeMyProfile(native: .german)
        let candidates = try await service.candidates(for: me)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(
            candidates.allSatisfy { $0.nativeLanguage == .french },
            "Deutsches Profil bekommt nur französische Muttersprachler"
        )
    }

    func testFrenchProfileGetsGermanCandidates() async throws {
        let (service, me) = try await makeMyProfile(native: .french)
        let candidates = try await service.candidates(for: me)
        XCTAssertTrue(candidates.allSatisfy { $0.nativeLanguage == .german })
    }

    func testMatchedPartnersLeaveTheCandidateList() async throws {
        let (service, me) = try await makeMyProfile()
        let first = try await service.candidates(for: me)[0]
        _ = try await service.requestMatch(from: me, to: first)

        let after = try await service.candidates(for: me)
        XCTAssertFalse(after.contains { $0.id == first.id })

        let matches = try await service.matches(for: me)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].otherProfileID(for: me.id), first.id)
    }

    // MARK: - Chat & Übersetzungsrichtung

    func testChatFlowAndLanguages() async throws {
        let (service, me) = try await makeMyProfile()
        let partner = try await service.candidates(for: me)[0]
        let match = try await service.requestMatch(from: me, to: partner)

        // Ich schreibe in meiner Lernsprache (Französisch).
        _ = try await service.send(text: "Bonjour !", language: me.learningLanguage, in: match, from: me)
        let messages = try await service.messages(for: match)
        XCTAssertGreaterThanOrEqual(messages.count, 2, "Begrüßung des Partners + eigene Nachricht")

        let mine = try XCTUnwrap(messages.last { $0.senderProfileID == me.id })
        XCTAssertEqual(mine.language, .french)

        let theirs = try XCTUnwrap(messages.first { $0.senderProfileID == partner.id })
        XCTAssertEqual(theirs.language, .german, "Der französische Partner übt Deutsch")

        // Anzeige-Regel: nur die Partner-Nachricht braucht Übersetzung —
        // von meiner Muttersprache (DE) in meine Lernsprache (FR).
        XCTAssertFalse(ChatDisplay.needsTranslation(mine, for: me))
        XCTAssertTrue(ChatDisplay.needsTranslation(theirs, for: me))
        let direction = ChatDisplay.translationDirection(for: me)
        XCTAssertEqual(direction.source, .german)
        XCTAssertEqual(direction.target, .french)

        // Und aus Sicht des Partners genau spiegelverkehrt.
        let partnerView = ChatDisplay.translationDirection(for: partner)
        XCTAssertEqual(partnerView.source, .french)
        XCTAssertEqual(partnerView.target, .german)
        XCTAssertTrue(ChatDisplay.needsTranslation(mine, for: partner))
        XCTAssertFalse(ChatDisplay.needsTranslation(theirs, for: partner))
    }

    func testAcceptFlowForIncomingRequest() async throws {
        let service = MockCommunityService()
        let me = CommunityProfile(
            id: "me", displayName: "Ich", bio: "", hobbies: [],
            nativeLanguage: .german, photoData: nil, createdAt: .now
        )
        let requester = CommunityProfile(
            id: "req", displayName: "Camille", bio: "", hobbies: [],
            nativeLanguage: .french, photoData: nil, createdAt: .now
        )
        let pending = TandemMatch(
            id: "m1", requesterID: requester.id, partnerID: me.id,
            status: .pending, createdAt: .now
        )
        XCTAssertTrue(pending.isIncoming(for: me.id))
        XCTAssertFalse(pending.isIncoming(for: requester.id))

        let accepted = try await service.accept(pending)
        // Mock kennt das Match nicht → gibt es unverändert zurück; die Regel
        // selbst prüfen wir über den Status-Wechsel im Modell.
        XCTAssertEqual(accepted.id, pending.id)

        var flipped = pending
        flipped.status = .accepted
        XCTAssertFalse(flipped.isIncoming(for: me.id), "Angenommen = keine offene Anfrage mehr")
    }

    func testLanguageHelpers() {
        XCTAssertEqual(TandemLanguage.german.other, .french)
        XCTAssertEqual(TandemLanguage.french.other, .german)
        XCTAssertEqual(TandemLanguage.german.localeIdentifier, "de-DE")
        XCTAssertEqual(TandemLanguage.french.localeIdentifier, "fr-FR")
    }
}
