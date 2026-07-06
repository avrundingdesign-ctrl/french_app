import XCTest
@testable import FrenchApp

/// Validiert die gebündelten Inhaltsdaten und die daraus gebauten Übungen —
/// das Sicherheitsnetz für die redaktionell gepflegten JSON-Dateien.
final class ContentTests: XCTestCase {
    private var content: ContentStore!
    private var factory: ExerciseFactory!

    override func setUpWithError() throws {
        content = try ContentStore(bundle: Bundle(for: ContentStore.self))
        factory = ExerciseFactory(content: content)
    }

    func testContentVolume() {
        XCTAssertGreaterThanOrEqual(content.vocabulary.count, 150)
        XCTAssertGreaterThanOrEqual(content.verbs.count, 30)
        XCTAssertGreaterThanOrEqual(content.grammarRules.count, 15)
        XCTAssertGreaterThanOrEqual(content.orderedLessons.count, 20)
    }

    func testVocabularyIDsAreUnique() {
        let ids = content.vocabulary.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testAllLessonReferencesResolve() {
        for lesson in content.orderedLessons {
            for vocabID in lesson.newVocab {
                XCTAssertNotNil(content.vocab(vocabID), "\(lesson.id): Vokabel \(vocabID) fehlt")
            }
            for grammarID in lesson.grammar ?? [] {
                XCTAssertNotNil(content.grammarByID[grammarID], "\(lesson.id): Regel \(grammarID) fehlt")
            }
        }
    }

    func testGrammarVerbTablesResolve() {
        for rule in content.grammarRules {
            for infinitive in rule.verbTables ?? [] {
                XCTAssertNotNil(content.conjugator.verb(infinitive), "\(rule.id): Verb \(infinitive) fehlt")
            }
        }
    }

    func testEveryLessonBuildsEnoughExercises() {
        for lesson in content.orderedLessons {
            let exercises = factory.exercises(for: lesson)
            XCTAssertGreaterThanOrEqual(
                exercises.count, 6,
                "\(lesson.id) hat nur \(exercises.count) Übungen"
            )
        }
    }

    func testBuiltExercisesAreWellFormed() {
        for lesson in content.orderedLessons {
            for exercise in factory.exercises(for: lesson) {
                switch exercise.kind {
                case .multipleChoice(let mc):
                    XCTAssertGreaterThanOrEqual(mc.options.count, 3, "\(exercise.id): zu wenige Optionen")
                    XCTAssertTrue(mc.options.indices.contains(mc.correctIndex), exercise.id)
                    XCTAssertEqual(Set(mc.options).count, mc.options.count, "\(exercise.id): doppelte Optionen")
                case .matching(let matching):
                    XCTAssertGreaterThanOrEqual(matching.pairs.count, 3, exercise.id)
                case .textInput(let input):
                    XCTAssertFalse(input.answer.isEmpty, exercise.id)
                    XCTAssertFalse(input.fullSolution.isEmpty, exercise.id)
                case .wordOrder(let order):
                    XCTAssertGreaterThanOrEqual(order.tokens.count, 3, exercise.id)
                    XCTAssertFalse(order.de.isEmpty, exercise.id)
                }
            }
        }
    }

    func testConjugationSpecsResolveToForms() {
        for lesson in content.orderedLessons {
            for spec in lesson.exercises where spec.type == .conjugation {
                let verb = content.conjugator.verb(spec.verb ?? "")
                XCTAssertNotNil(verb, "\(lesson.id): Verb \(spec.verb ?? "?") fehlt")
                if let verb {
                    let tense = Conjugator.Tense(rawValue: spec.tense ?? "present") ?? .present
                    let form = content.conjugator.form(of: verb, tense: tense, person: spec.person ?? -1)
                    XCTAssertNotNil(form, "\(lesson.id): keine Form für \(verb.infinitive)/\(tense)")
                }
            }
        }
    }

    func testSequentialUnlocking() {
        let first = content.orderedLessons[0]
        let second = content.orderedLessons[1]

        let empty = ProgressSnapshot(progress: [], content: content)
        XCTAssertTrue(empty.isUnlocked(first))
        XCTAssertFalse(empty.isUnlocked(second))

        let progressed = ProgressSnapshot(
            progress: [LessonProgress(lessonID: first.id, bestScore: 1.0)],
            content: content
        )
        XCTAssertTrue(progressed.isUnlocked(second))
        XCTAssertEqual(progressed.nextLesson?.id, second.id)
    }

    func testMistakeReferenceRebuildsExercise() throws {
        let lesson = content.orderedLessons[0]
        let exercises = factory.exercises(for: lesson)
        let target = try XCTUnwrap(exercises.first)
        let rebuilt = factory.exercise(for: target.ref)
        XCTAssertNotNil(rebuilt)
        XCTAssertEqual(rebuilt?.ref, target.ref)
    }

    func testStaleMistakeReferenceReturnsNil() {
        let ref = ExerciseRef(lessonID: "gibt_es_nicht", exerciseIndex: 0, subIndex: 0)
        XCTAssertNil(factory.exercise(for: ref))
    }
}
