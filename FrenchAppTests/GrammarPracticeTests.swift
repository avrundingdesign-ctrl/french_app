import XCTest
@testable import FrenchApp

/// Grammatik-Training: jede Regel liefert Übungen, Musterlösungen werden
/// akzeptiert, gemischte Sessions bleiben ohne Duplikate.
final class GrammarPracticeTests: XCTestCase {
    private var content: ContentStore!
    private var practice: GrammarPractice!

    override func setUpWithError() throws {
        content = try ContentStore(bundle: Bundle(for: ContentStore.self))
        practice = GrammarPractice(content: content)
    }

    func testEveryRuleYieldsExercises() {
        for rule in content.grammarRules {
            let exercises = practice.allExercises(for: rule)
            XCTAssertFalse(
                exercises.isEmpty,
                "\(rule.id): keine Übungen — weder aus Lektionen noch aus Beispielsätzen"
            )
        }
    }

    func testCanonicalAnswersAreAccepted() {
        for rule in content.grammarRules {
            for exercise in practice.allExercises(for: rule) {
                guard case .textInput(let input) = exercise.kind else { continue }
                XCTAssertNotEqual(
                    input.check(input.answer), AnswerChecker.Result.wrong,
                    "\(exercise.id): Musterlösung «\(input.answer)» wird nicht akzeptiert"
                )
            }
        }
    }

    func testExamplesBecomeWordOrderExercises() throws {
        // Die Beispielsätze der Regel tauchen als Satzbau-Übungen auf.
        let rule = try XCTUnwrap(content.grammarByID["g_lequel"])
        let wordOrders = practice.allExercises(for: rule).compactMap { exercise -> WordOrderExercise? in
            guard case .wordOrder(let order) = exercise.kind else { return nil }
            return order
        }
        let sentences = Set(wordOrders.map { $0.tokens.joined(separator: " ") })
        for example in rule.examples where example.fr.split(separator: " ").count >= 3 {
            XCTAssertTrue(sentences.contains(example.fr), "Beispiel «\(example.fr)» fehlt als Übung")
        }
    }

    func testMixedSessionHasNoDuplicatesAndRespectsLimit() {
        let session = practice.session(rules: content.grammarRules, count: 10)
        XCTAssertEqual(session.count, 10)
        XCTAssertEqual(Set(session.map(\.ref)).count, 10, "Duplikate in der Session")
    }

    func testSessionWithNoRulesIsEmpty() {
        XCTAssertTrue(practice.session(rules: []).isEmpty)
    }

    func testOnlyGrammarSpecTypesAreUsed() {
        // Keine Vokabel-Übungen im Grammatik-Training.
        for rule in content.grammarRules.prefix(10) {
            for exercise in practice.allExercises(for: rule) {
                if case .matching = exercise.kind {
                    XCTFail("\(exercise.id): Matching gehört nicht ins Grammatik-Training")
                }
            }
        }
    }
}
