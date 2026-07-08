import Foundation

/// Baut Übungssessions zu Grammatikthemen: die Grammatik-Übungen der
/// verknüpften Lektionen plus Satzbau-Übungen aus den Beispielsätzen der Regel.
/// Nur freigeschaltete Regeln (Lektion abgeschlossen) kommen ins Training —
/// das entscheidet der Aufrufer über die übergebene Regelliste.
struct GrammarPractice {
    /// Übungstypen, die Grammatik abfragen — Vokabel-Typen bleiben draußen.
    static let grammarSpecTypes: Set<ExerciseSpecType> = [
        .cloze, .conjugation, .mcSentence, .errorCorrection, .wordOrder, .translate,
    ]

    let content: ContentStore
    private let factory: ExerciseFactory

    init(content: ContentStore = .shared) {
        self.content = content
        self.factory = ExerciseFactory(content: content)
    }

    /// Alle Übungen zu einer Regel (ungemischt, ohne Limit).
    func allExercises(for rule: GrammarRule) -> [RuntimeExercise] {
        var result: [RuntimeExercise] = []

        for lesson in content.lessons(covering: rule.id) {
            for (index, spec) in lesson.exercises.enumerated()
            where Self.grammarSpecTypes.contains(spec.type) {
                let ref = ExerciseRef(lessonID: lesson.id, exerciseIndex: index, subIndex: 0)
                if let exercise = factory.standaloneExercise(spec: spec, ref: ref) {
                    result.append(exercise)
                }
            }
        }

        // Beispielsätze der Regel als Satzbau-Übung.
        for (index, example) in rule.examples.enumerated() {
            guard example.fr.split(separator: " ").count >= 3 else { continue }
            let spec = ExerciseSpec(type: .wordOrder, fr: example.fr, de: example.de)
            let ref = ExerciseRef(lessonID: rule.id, exerciseIndex: 1000 + index, subIndex: 0)
            if let exercise = factory.standaloneExercise(spec: spec, ref: ref) {
                result.append(exercise)
            }
        }
        return result
    }

    /// Gemischte Session über die übergebenen (freigeschalteten) Regeln.
    func session(rules: [GrammarRule], count: Int = 10) -> [RuntimeExercise] {
        var seen = Set<ExerciseRef>()
        return Array(
            rules.flatMap { allExercises(for: $0) }
                .shuffled()
                .filter { seen.insert($0.ref).inserted }
                .prefix(count)
        )
    }
}
