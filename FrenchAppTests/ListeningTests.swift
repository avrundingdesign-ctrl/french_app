import XCTest
@testable import FrenchApp

/// Hörtraining: Satz-Pool, Übungsgeneratoren und Lücken-Zerlegung.
final class ListeningTests: XCTestCase {
    private var content: ContentStore!
    private var trainer: ListeningTrainer!

    override func setUpWithError() throws {
        content = try ContentStore(bundle: Bundle(for: ContentStore.self))
        trainer = ListeningTrainer(content: content)
    }

    // MARK: - Satz-Pool

    func testSentencePoolIsSubstantialAndGrowsWithLevel() {
        XCTAssertGreaterThanOrEqual(
            trainer.sentences(upTo: .a1).count, 20,
            "A1 braucht genug Sätze für abwechslungsreiche Sessions"
        )
        var previous = 0
        for level in [CEFRLevel.a1, .a2, .b1, .b2] {
            let count = trainer.sentences(upTo: level).count
            XCTAssertGreaterThanOrEqual(count, previous, "\(level.rawValue) darf den Pool nicht schrumpfen")
            previous = count
        }
    }

    func testPoolSentencesAreTypeable() {
        for sentence in trainer.sentences {
            let normalized = AnswerChecker.normalize(sentence.fr)
            XCTAssertTrue(
                normalized.unicodeScalars.allSatisfy { ListeningTrainer.typeable.contains($0) },
                "«\(sentence.fr)» enthält untippbare Zeichen"
            )
            XCTAssertFalse(sentence.de.isEmpty, "«\(sentence.fr)» ohne Übersetzung")
        }
    }

    // MARK: - Dictée

    func testDictationExercisesSpeakExactlyWhatTheyExpect() {
        let exercises = trainer.dictationExercises(upTo: .a1, count: 8)
        XCTAssertEqual(exercises.count, 8)
        for exercise in exercises {
            guard case .textInput(let input) = exercise.kind else {
                return XCTFail("\(exercise.id): kein Freitext")
            }
            XCTAssertEqual(exercise.audio, input.answer, "Gesprochen = erwartet")
            XCTAssertNotEqual(input.check(input.answer), AnswerChecker.Result.wrong)
            // Satzzeichen dürfen bei der Dictée nicht zählen (Checker normalisiert).
            let stripped = AnswerChecker.normalize(input.answer)
            XCTAssertNotEqual(input.check(stripped), AnswerChecker.Result.wrong)
        }
    }

    // MARK: - Hör-Lückentext

    func testClozeExercisesReassembleOriginalSentence() {
        let exercises = trainer.clozeExercises(upTo: .b2, count: 12)
        XCTAssertEqual(exercises.count, 12)
        for exercise in exercises {
            guard case .textInput(let input) = exercise.kind else {
                return XCTFail("\(exercise.id): kein Freitext")
            }
            XCTAssertEqual(
                input.prefix + input.answer + input.suffix, exercise.audio,
                "Lücke muss den Originalsatz rekonstruieren"
            )
            XCTAssertGreaterThanOrEqual(input.answer.count, 4)
            XCTAssertTrue(input.answer.allSatisfy(\.isLetter))
            XCTAssertNotEqual(input.check(input.answer), AnswerChecker.Result.wrong)
        }
    }

    func testGapSplitKeepsPunctuationOutsideTheGap() throws {
        let split = try XCTUnwrap(ListeningTrainer.gapSplit("Nous mangeons une baguette."))
        XCTAssertEqual(split.word, "mangeons")
        XCTAssertEqual(split.prefix, "Nous ")
        XCTAssertEqual(split.suffix, " une baguette.")

        let apostrophe = try XCTUnwrap(ListeningTrainer.gapSplit("J'aime le fromage."))
        XCTAssertEqual(apostrophe.word, "fromage")
        XCTAssertEqual(apostrophe.suffix, ".")

        XCTAssertNil(ListeningTrainer.gapSplit("Il y a un an"), "Kein Wort ab 4 Buchstaben → keine Lücke")
    }

    // MARK: - Minimal-Paare

    func testMinimalPairExercisesSpeakOneOfTheTwoOptions() {
        XCTAssertGreaterThanOrEqual(content.minimalPairs.count, 20)
        let exercises = trainer.minimalPairExercises(count: 10)
        XCTAssertEqual(exercises.count, 10)
        for exercise in exercises {
            guard case .multipleChoice(let mc) = exercise.kind else {
                return XCTFail("\(exercise.id): kein Multiple Choice")
            }
            XCTAssertEqual(mc.options.count, 2)
            let spokenOption = mc.options[mc.correctIndex]
            XCTAssertTrue(
                spokenOption.hasPrefix(exercise.audio + " —"),
                "\(exercise.id): gesprochen «\(exercise.audio)», korrekte Option «\(spokenOption)»"
            )
        }
    }

    func testMinimalPairWordsDiffer() {
        for pair in content.minimalPairs {
            XCTAssertNotEqual(pair.a, pair.b, "\(pair.a): identisches Paar")
            XCTAssertNotEqual(
                AnswerChecker.normalize(pair.a), AnswerChecker.normalize(pair.b),
                "\(pair.a)/\(pair.b): nach Normalisierung identisch"
            )
        }
    }
}
