import Foundation

/// Kanonisches SM-2 (Woźniak 1987) — pure Funktionen, keine Seiteneffekte.
///
/// Bewertungsqualität q ∈ 0…5. In der App auf vier Buttons gemappt:
/// Nochmal = 2, Schwer = 3, Gut = 4, Einfach = 5 (siehe README).
enum SM2 {
    static let startEaseFactor = 2.5
    static let minimumEaseFactor = 1.3

    struct State: Equatable {
        var easeFactor: Double
        var repetitions: Int
        var interval: Int
    }

    /// Wendet eine Bewertung an und liefert den Folgezustand.
    ///
    /// - q ≥ 3: Intervallfolge 1 → 6 → round(interval × EF), Wiederholungszähler +1.
    /// - q < 3: Wiederholungszähler zurück auf 0, Intervall 1 Tag.
    /// - Der Ease-Faktor wird bei jeder Bewertung aktualisiert (Untergrenze 1.3);
    ///   das neue Intervall nutzt den bereits aktualisierten Ease-Faktor.
    static func review(_ state: State, quality q: Int) -> State {
        let q = max(0, min(5, q))

        var ease = state.easeFactor + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02))
        if ease < minimumEaseFactor { ease = minimumEaseFactor }

        guard q >= 3 else {
            return State(easeFactor: ease, repetitions: 0, interval: 1)
        }

        let interval: Int
        switch state.repetitions {
        case 0: interval = 1
        case 1: interval = 6
        default: interval = max(1, Int((Double(state.interval) * ease).rounded()))
        }
        return State(easeFactor: ease, repetitions: state.repetitions + 1, interval: interval)
    }
}

/// Die vier Bewertungsbuttons der Review-Session, gemappt auf SM-2-Qualitäten.
enum ReviewGrade: Int, CaseIterable, Identifiable {
    case again = 2
    case hard = 3
    case good = 4
    case easy = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .again: return "Nochmal"
        case .hard: return "Schwer"
        case .good: return "Gut"
        case .easy: return "Einfach"
        }
    }

    var isCorrect: Bool { rawValue >= 3 }
}
