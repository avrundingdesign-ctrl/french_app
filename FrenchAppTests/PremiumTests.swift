import XCTest
@testable import FrenchApp

/// Paywall-Gating (Phase 6): Die Produktentscheidungen aus der ROADMAP
/// als Tests — Einstieg und Netzwerk frei, Tiefe kostet.
final class PremiumTests: XCTestCase {
    // MARK: - Lernpfad

    func testLessonsA1AndA2AreFree() {
        XCTAssertFalse(PremiumGate.lessonRequiresPremium(level: .a1))
        XCTAssertFalse(PremiumGate.lessonRequiresPremium(level: .a2))
    }

    func testLessonsFromB1RequirePremium() {
        XCTAssertTrue(PremiumGate.lessonRequiresPremium(level: .b1))
        XCTAssertTrue(PremiumGate.lessonRequiresPremium(level: .b2))
    }

    // MARK: - Wortschatz-Pakete

    func testBasicPacksAreFreePremiumPacksAreNot() {
        XCTAssertFalse(PremiumGate.packRequiresPremium(level: .a1))
        XCTAssertFalse(PremiumGate.packRequiresPremium(level: .a2))
        XCTAssertTrue(PremiumGate.packRequiresPremium(level: .b1))
        XCTAssertTrue(PremiumGate.packRequiresPremium(level: .b2))
    }

    // MARK: - Prüfungen

    func testExamsUpToB1AreFree() {
        XCTAssertFalse(PremiumGate.examRequiresPremium(level: .a1))
        XCTAssertFalse(PremiumGate.examRequiresPremium(level: .a2))
        XCTAssertFalse(PremiumGate.examRequiresPremium(level: .b1))
    }

    func testExamsB2AndC1RequirePremium() {
        XCTAssertTrue(PremiumGate.examRequiresPremium(level: .b2))
        XCTAssertTrue(PremiumGate.examRequiresPremium(level: .c1))
    }

    // MARK: - Vertiefungen

    func testAllChallengesRequirePremium() {
        for level in CEFRLevel.allCases {
            XCTAssertTrue(PremiumGate.challengeRequiresPremium(level: level), level.rawValue)
        }
    }

    // MARK: - Konsistenz mit dem Content

    /// Die freie Zone muss ein vollständiges, sinnvolles Erlebnis bleiben:
    /// beide Kursrichtungen brauchen freie A1/A2-Lektionen, und jede
    /// Richtung behält mindestens eine frei erreichbare Prüfung.
    func testFreeTierIsSubstantialInBothDirections() throws {
        for direction in CourseDirection.allCases {
            let content = try ContentStore(bundle: Bundle(for: ContentStore.self), direction: direction)
            let freeLessons = content.orderedLessons.filter { lesson in
                let level = content.units.first { $0.lessons.contains(lesson) }?.level ?? .a1
                return !PremiumGate.lessonRequiresPremium(level: level)
            }
            XCTAssertGreaterThanOrEqual(freeLessons.count, 48, "\(direction): A1+A2 müssen frei bleiben")

            let freeExams = content.exams.filter { !PremiumGate.examRequiresPremium(level: $0.level) }
            XCTAssertFalse(freeExams.isEmpty, "\(direction): mindestens eine freie Prüfung")

            let freePacks = content.packs.filter { !PremiumGate.packRequiresPremium(level: $0.level) }
            XCTAssertFalse(freePacks.isEmpty, "\(direction): Basis-Pakete müssen frei bleiben")
        }
    }
}
