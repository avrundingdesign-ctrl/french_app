import XCTest
import SwiftData
@testable import FrenchApp

/// SRS-Ablauf über SwiftData (in-memory): Einspeisen, Tagespensum, Fehler-Reset.
@MainActor
final class SRSTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([ReviewState.self, LessonProgress.self, MistakeRecord.self, UserSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
    }

    func testEnrollCreatesStatesOnce() {
        let created = SRSService.enroll(vocabIDs: ["v_a", "v_b"], context: context)
        XCTAssertEqual(created, 2)
        let again = SRSService.enroll(vocabIDs: ["v_b", "v_c"], context: context)
        XCTAssertEqual(again, 1)
        XCTAssertEqual(SRSService.fetchStates(context: context).count, 3)
    }

    func testQueueRespectsDailyNewCardLimit() {
        let settings = UserSettings()
        settings.newCardsPerDay = 2
        SRSService.enroll(vocabIDs: ["v_a", "v_b", "v_c", "v_d"], context: context)
        let states = SRSService.fetchStates(context: context)

        let queue = SRSService.buildQueue(states: states, settings: settings)
        XCTAssertEqual(queue.due.count, 0)
        XCTAssertEqual(queue.fresh.count, 2)
    }

    func testGradeSchedulesNextReview() {
        SRSService.enroll(vocabIDs: ["v_a"], context: context)
        let state = SRSService.fetchStates(context: context)[0]

        SRSService.apply(grade: .good, to: state)
        XCTAssertEqual(state.repetitions, 1)
        XCTAssertEqual(state.interval, 1)
        XCTAssertNotNil(state.firstReviewedAt)
        XCTAssertTrue(state.nextReview > .now)

        // Nach der ersten Bewertung zählt die Karte nicht mehr als neu …
        let settings = UserSettings()
        let queue = SRSService.buildQueue(states: [state], settings: settings)
        XCTAssertTrue(queue.fresh.isEmpty)
        // … und ist erst morgen wieder fällig.
        XCTAssertTrue(queue.due.isEmpty)
    }

    func testMistakeResetMakesCardDueAgain() {
        SRSService.enroll(vocabIDs: ["v_a"], context: context)
        let state = SRSService.fetchStates(context: context)[0]
        SRSService.apply(grade: .good, to: state)
        SRSService.apply(grade: .good, to: state)
        XCTAssertEqual(state.repetitions, 2)
        let easeBefore = state.easeFactor

        SRSService.resetForMistake(vocabID: "v_a", context: context)
        XCTAssertEqual(state.repetitions, 0)
        XCTAssertEqual(state.interval, 0)
        XCTAssertTrue(state.isDue(at: .now))
        XCTAssertEqual(state.lapses, 1)
        // Der Ease-Faktor bleibt unangetastet — Lektionsfehler sind keine Review-Bewertung.
        XCTAssertEqual(state.easeFactor, easeBefore, accuracy: 0.0001)
    }

    func testPreviewIntervalMatchesApply() {
        SRSService.enroll(vocabIDs: ["v_a"], context: context)
        let state = SRSService.fetchStates(context: context)[0]
        let preview = SRSService.previewInterval(for: .good, state: state)
        SRSService.apply(grade: .good, to: state)
        XCTAssertEqual(state.interval, preview)
    }
}
