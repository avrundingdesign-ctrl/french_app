import XCTest
import SwiftData
@testable import FrenchApp

/// Vertiefungskapitel: Aufbau, Musterlösungen und Fortschritts-Persistenz.
@MainActor
final class ChallengeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var content: ContentStore!

    override func setUpWithError() throws {
        let schema = Schema([ChallengeProgress.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
        content = try ContentStore(bundle: Bundle(for: ContentStore.self))
    }

    func testEveryLessonLevelHasAChallengeChapter() {
        for level in content.levels {
            XCTAssertNotNil(
                content.challengeByLevel[level],
                "\(level.rawValue): kein Vertiefungskapitel"
            )
        }
    }

    func testEveryChallengeQuestionBuildsAndAcceptsCanonicalAnswer() {
        let factory = ExerciseFactory(content: content)
        for chapter in content.challenges {
            var builtCount = 0
            for (taskIndex, task) in chapter.tasks.enumerated() {
                for (questionIndex, spec) in task.questions.enumerated() {
                    let ref = ExerciseRef(
                        lessonID: chapter.id,
                        exerciseIndex: taskIndex,
                        subIndex: questionIndex
                    )
                    guard let exercise = factory.standaloneExercise(spec: spec, ref: ref) else {
                        XCTFail("\(chapter.id) t\(taskIndex) q\(questionIndex): nicht baubar")
                        continue
                    }
                    builtCount += 1
                    if case .textInput(let input) = exercise.kind {
                        XCTAssertNotEqual(
                            input.check(input.answer), AnswerChecker.Result.wrong,
                            "\(exercise.id): Musterlösung «\(input.answer)» wird nicht akzeptiert"
                        )
                    }
                }
            }
            XCTAssertEqual(builtCount, chapter.questionCount, chapter.id)
            XCTAssertGreaterThanOrEqual(builtCount, 12, "\(chapter.id): zu wenige Aufgaben")
        }
    }

    func testChallengeTextAnswersAreTypeable() {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789 éèêàçùâîôûëïöüœ'-")
        let factory = ExerciseFactory(content: content)
        for chapter in content.challenges {
            for (taskIndex, task) in chapter.tasks.enumerated() {
                for (questionIndex, spec) in task.questions.enumerated() {
                    let ref = ExerciseRef(lessonID: chapter.id, exerciseIndex: taskIndex, subIndex: questionIndex)
                    guard let exercise = factory.standaloneExercise(spec: spec, ref: ref),
                          case .textInput(let input) = exercise.kind
                    else { continue }
                    let normalized = AnswerChecker.normalize(input.answer)
                    XCTAssertTrue(
                        normalized.unicodeScalars.allSatisfy { allowed.contains($0) },
                        "\(exercise.id): Antwort «\(normalized)» enthält untippbare Zeichen"
                    )
                }
            }
        }
    }

    func testChallengeProgressKeepsBestScore() throws {
        let progress = ChallengeProgress(chapterID: "challenge_a1", bestScore: 0.6)
        context.insert(progress)

        // Zweiter, besserer Lauf: bester Score bleibt maximal.
        progress.bestScore = max(progress.bestScore, 0.9)
        progress.timesCompleted += 1
        // Dritter, schlechterer Lauf ändert den Bestwert nicht.
        progress.bestScore = max(progress.bestScore, 0.5)
        progress.timesCompleted += 1

        let stored = try context.fetch(FetchDescriptor<ChallengeProgress>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].bestScore, 0.9, accuracy: 0.001)
        XCTAssertEqual(stored[0].timesCompleted, 3)
    }

    /// Die Vertiefung nutzt dieselbe Freischaltung wie die Prüfung:
    /// alle Lektionen des Niveaus müssen abgeschlossen sein.
    func testChallengeUnlockMatchesExamGate() {
        let empty = ProgressSnapshot(progress: [], content: content)
        XCTAssertFalse(empty.isExamUnlocked(.a1))

        let allA1 = content.lessons(for: .a1).map {
            LessonProgress(lessonID: $0.id, bestScore: 1.0)
        }
        let done = ProgressSnapshot(progress: allA1, content: content)
        XCTAssertTrue(done.isExamUnlocked(.a1))
    }
}
