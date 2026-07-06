import XCTest
@testable import FrenchApp

/// Kanonisches SM-2-Verhalten (Spec §3): Intervallfolge, Ease-Faktor-Formel, Untergrenze.
final class SM2Tests: XCTestCase {
    private let fresh = SM2.State(easeFactor: 2.5, repetitions: 0, interval: 0)

    func testFirstCorrectReviewGivesOneDay() {
        let result = SM2.review(fresh, quality: 4)
        XCTAssertEqual(result.interval, 1)
        XCTAssertEqual(result.repetitions, 1)
        XCTAssertEqual(result.easeFactor, 2.5, accuracy: 0.0001) // q=4 ändert EF nicht
    }

    func testSecondCorrectReviewGivesSixDays() {
        let first = SM2.review(fresh, quality: 4)
        let second = SM2.review(first, quality: 4)
        XCTAssertEqual(second.interval, 6)
        XCTAssertEqual(second.repetitions, 2)
    }

    func testThirdReviewMultipliesByEase() {
        var state = SM2.review(fresh, quality: 4)
        state = SM2.review(state, quality: 4)
        state = SM2.review(state, quality: 4)
        // round(6 × 2.5) = 15
        XCTAssertEqual(state.interval, 15)
        XCTAssertEqual(state.repetitions, 3)
    }

    func testEasyIncreasesEaseByTenth() {
        let result = SM2.review(fresh, quality: 5)
        XCTAssertEqual(result.easeFactor, 2.6, accuracy: 0.0001)
    }

    func testHardDecreasesEase() {
        let result = SM2.review(fresh, quality: 3)
        // 2.5 + (0.1 − 2 × (0.08 + 2 × 0.02)) = 2.5 − 0.14
        XCTAssertEqual(result.easeFactor, 2.36, accuracy: 0.0001)
    }

    func testFailureResetsRepetitionsAndSchedulesTomorrow() {
        var state = SM2.review(fresh, quality: 4)
        state = SM2.review(state, quality: 4)
        let failed = SM2.review(state, quality: 2)
        XCTAssertEqual(failed.repetitions, 0)
        XCTAssertEqual(failed.interval, 1)
        // 2.5 + (0.1 − 3 × (0.08 + 3 × 0.02)) = 2.5 − 0.32
        XCTAssertEqual(failed.easeFactor, 2.18, accuracy: 0.0001)
    }

    func testEaseNeverDropsBelowFloor() {
        var state = SM2.State(easeFactor: 1.31, repetitions: 5, interval: 30)
        for _ in 0..<10 {
            state = SM2.review(state, quality: 2)
        }
        XCTAssertEqual(state.easeFactor, SM2.minimumEaseFactor, accuracy: 0.0001)
    }

    func testQualityIsClamped() {
        let tooHigh = SM2.review(fresh, quality: 99)
        XCTAssertEqual(tooHigh.easeFactor, 2.6, accuracy: 0.0001) // wie q=5
        let tooLow = SM2.review(fresh, quality: -3)
        XCTAssertEqual(tooLow.repetitions, 0) // wie q=0
        XCTAssertEqual(tooLow.interval, 1)
    }

    func testGradeMapping() {
        XCTAssertFalse(ReviewGrade.again.isCorrect)
        XCTAssertTrue(ReviewGrade.hard.isCorrect)
        XCTAssertTrue(ReviewGrade.good.isCorrect)
        XCTAssertTrue(ReviewGrade.easy.isCorrect)
    }
}
