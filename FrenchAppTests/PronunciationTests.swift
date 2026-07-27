import XCTest
@testable import FrenchApp

/// Sprechtraining: Bewertungslogik (Scorer) und Übungspool (Trainer) —
/// beides pur, ohne Mikrofon oder Spracherkennung.
final class PronunciationTests: XCTestCase {
    private var content: ContentStore!

    override func setUpWithError() throws {
        content = try ContentStore(bundle: Bundle(for: ContentStore.self))
    }

    // MARK: - Levenshtein & Ähnlichkeit

    func testLevenshteinBasics() {
        XCTAssertEqual(PronunciationScorer.levenshtein("", ""), 0)
        XCTAssertEqual(PronunciationScorer.levenshtein("abc", ""), 3)
        XCTAssertEqual(PronunciationScorer.levenshtein("", "abc"), 3)
        XCTAssertEqual(PronunciationScorer.levenshtein("bonjour", "bonjour"), 0)
        XCTAssertEqual(PronunciationScorer.levenshtein("bonjour", "bonjours"), 1)
        XCTAssertEqual(PronunciationScorer.levenshtein("chat", "chien"), 3)
    }

    func testSimilarityRange() {
        XCTAssertEqual(PronunciationScorer.similarity("bonjour", "bonjour"), 1)
        XCTAssertEqual(PronunciationScorer.similarity("", ""), 1)
        XCTAssertEqual(PronunciationScorer.similarity("abc", "xyz"), 0)
        let close = PronunciationScorer.similarity("bonjour", "bonjours")
        XCTAssertGreaterThan(close, 0.8)
        XCTAssertLessThan(close, 1)
    }

    // MARK: - Bewertung

    func testPerfectMatchScoresFull() {
        let result = PronunciationScorer.assess(target: "le pain", transcript: "le pain")
        XCTAssertEqual(result.score, 1)
        XCTAssertTrue(result.isPass)
        XCTAssertEqual(result.verdict, .excellent)
        XCTAssertTrue(result.words.allSatisfy(\.matched))
    }

    func testCaseAndPunctuationDoNotCount() {
        let result = PronunciationScorer.assess(
            target: "Bonjour, ça va ?",
            transcript: "bonjour ça va"
        )
        XCTAssertEqual(result.score, 1, "Groß-/Kleinschreibung und Satzzeichen sind egal")
        XCTAssertTrue(result.words.allSatisfy(\.matched))
    }

    func testCurlyApostropheIsNormalized() {
        let result = PronunciationScorer.assess(target: "j'ai faim", transcript: "j’ai faim")
        XCTAssertEqual(result.score, 1)
    }

    func testEmptyTranscriptScoresZero() {
        let result = PronunciationScorer.assess(target: "le pain", transcript: "")
        XCTAssertEqual(result.score, 0)
        XCTAssertFalse(result.isPass)
        XCTAssertTrue(result.words.allSatisfy { !$0.matched })
    }

    func testWrongWordScoresLow() {
        let result = PronunciationScorer.assess(target: "la voiture", transcript: "le fromage")
        XCTAssertLessThan(result.score, 0.6)
        XCTAssertFalse(result.isPass)
    }

    func testPartialSentenceMarksMissingWords() {
        let result = PronunciationScorer.assess(
            target: "Je mange une pomme",
            transcript: "je mange"
        )
        XCTAssertEqual(result.words.count, 4)
        XCTAssertTrue(result.words[0].matched, "«Je» wurde gesprochen")
        XCTAssertTrue(result.words[1].matched, "«mange» wurde gesprochen")
        XCTAssertFalse(result.words[2].matched, "«une» fehlt")
        XCTAssertFalse(result.words[3].matched, "«pomme» fehlt")
        XCTAssertFalse(result.isPass, "Halber Satz reicht nicht")
    }

    func testTranscriptWordsAreConsumedOnlyOnce() {
        // "le le" darf nicht beide Zielwörter abdecken, wenn nur ein "le" kam.
        let result = PronunciationScorer.assess(target: "le le pain", transcript: "le pain")
        let matchedCount = result.words.filter(\.matched).count
        XCTAssertEqual(matchedCount, 2, "Ein gesprochenes Wort deckt nur ein Zielwort ab")
    }

    func testRepeatedWordsInTargetKeepStableIDs() {
        let result = PronunciationScorer.assess(target: "très très bien", transcript: "très bien")
        XCTAssertEqual(Set(result.words.map(\.id)).count, 3, "IDs müssen eindeutig sein")
    }

    func testAccentSlipStillScoresWell() {
        let result = PronunciationScorer.assess(target: "le café", transcript: "le cafe")
        XCTAssertGreaterThanOrEqual(result.score, 0.85, "Ein Akzent-Zeichen darf nicht durchfallen lassen")
    }

    // MARK: - Übungspool

    func testWordPoolIsSubstantialAndLevelFiltered() {
        let trainer = PronunciationTrainer(content: content)
        let a1 = trainer.wordItems(upTo: .a1)
        XCTAssertGreaterThanOrEqual(a1.count, 50, "A1 braucht genug Wörter")
        for item in a1 {
            XCTAssertLessThanOrEqual(item.level, CEFRLevel.a1)
            XCTAssertFalse(item.text.isEmpty)
            XCTAssertFalse(item.translation.isEmpty)
        }
        XCTAssertGreaterThanOrEqual(trainer.wordItems(upTo: .b2).count, a1.count)
    }

    func testWordPoolHasNoDuplicates() {
        let items = PronunciationTrainer(content: content).wordItems(upTo: .b2)
        XCTAssertEqual(Set(items.map(\.text)).count, items.count)
    }

    func testSentencePoolMatchesListeningPool() {
        let trainer = PronunciationTrainer(content: content)
        let listening = ListeningTrainer(content: content)
        XCTAssertEqual(
            trainer.sentenceItems(upTo: .b1).count,
            listening.sentences(upTo: .b1).count,
            "Sprechtraining nutzt denselben Satz-Pool wie das Hörtraining"
        )
    }

    func testItemsRespectRequestedCount() {
        let trainer = PronunciationTrainer(content: content)
        XCTAssertEqual(trainer.items(mode: .words, upTo: .a1, count: 8).count, 8)
        XCTAssertEqual(trainer.items(mode: .sentences, upTo: .a1, count: 8).count, 8)
    }

    // MARK: - Übungs-Audio (Lautsprecher-Buttons)

    func testLessonExercisesCarrySpeechTexts() throws {
        let factory = ExerciseFactory(content: content)
        let lesson = try XCTUnwrap(content.units.first?.lessons.first)
        let exercises = factory.exercises(for: lesson)
        XCTAssertFalse(exercises.isEmpty)

        // Jede Übung macht ihr Lernsprachen-Material hörbar: als Prompt-Audio,
        // als Lösungs-Audio fürs Feedback oder (Matching) pro Paar.
        for exercise in exercises {
            switch exercise.kind {
            case .multipleChoice(let mc):
                XCTAssertTrue(
                    mc.promptAudio != nil || mc.solutionAudio != nil,
                    "\(exercise.id): MC ohne jedes Audio"
                )
                if let audio = mc.promptAudio {
                    XCTAssertEqual(audio.language, "fr-FR")
                    XCTAssertFalse(audio.text.contains("___"), "Lückentexte nicht vorlesen")
                }
            case .textInput(let input):
                let audio = try XCTUnwrap(input.solutionAudio, "\(exercise.id): Lösung muss hörbar sein")
                XCTAssertEqual(audio.text, input.fullSolution)
            case .wordOrder(let order):
                let audio = try XCTUnwrap(order.solutionAudio)
                XCTAssertEqual(audio.text, order.tokens.joined(separator: " "))
            case .matching(let matching):
                XCTAssertEqual(matching.audioLanguage, "fr-FR")
                for pair in matching.pairs {
                    XCTAssertEqual(matching.speech(for: pair)?.text, pair.fr)
                }
            }
        }
    }

    func testExamExercisesCarryNoAudio() throws {
        let factory = ExerciseFactory(content: content)
        let exam = try XCTUnwrap(content.exams.first)
        for (sectionIndex, section) in exam.sections.enumerated() {
            for (taskIndex, task) in section.tasks.enumerated() {
                for (questionIndex, spec) in task.questions.enumerated() {
                    let ref = ExerciseRef(
                        lessonID: exam.id,
                        exerciseIndex: sectionIndex * 100 + taskIndex,
                        subIndex: questionIndex
                    )
                    guard let exercise = factory.standaloneExercise(spec: spec, ref: ref, includeAudio: false) else { continue }
                    XCTAssertNil(exercise.kind.feedbackAudio, "\(exercise.id): Prüfung darf nicht vorlesen")
                    if case .multipleChoice(let mc) = exercise.kind {
                        XCTAssertNil(mc.promptAudio)
                    }
                }
            }
        }
    }
}
