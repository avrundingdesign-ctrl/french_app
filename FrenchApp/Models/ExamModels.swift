import Foundation

// MARK: - Niveau-Prüfungen (DELF-Stil)

/// Aufbau nach dem Vorbild der offiziellen DELF-Prüfungen: vier Teile à 25 Punkte,
/// bestanden ab 50/100 mit mindestens 5/25 in jedem Teil. Mündliche Produktion und
/// freie Aufsätze entfallen — der Schreibteil nutzt die automatisch prüfbaren
/// DELF-Formate (Formular ausfüllen, geführte Sätze).
struct ExamFile: Codable {
    let exams: [ExamDefinition]
}

struct ExamDefinition: Codable, Identifiable, Hashable {
    let id: String
    let level: CEFRLevel
    /// Gesamtzeit; nach Ablauf wird automatisch abgegeben.
    let durationMinutes: Int
    let sections: [ExamSection]

    static let passThreshold = 50.0
    static let sectionMinimum = 5.0
    static let sectionPoints = 25.0
}

enum ExamSectionKind: String, Codable, CaseIterable {
    case listening
    case reading
    case language
    case writing

    var germanTitle: String {
        switch self {
        case .listening: return "Hörverstehen"
        case .reading: return "Leseverstehen"
        case .language: return "Grammatik & Strukturen"
        case .writing: return "Schreiben"
        }
    }

    var frenchTitle: String {
        switch self {
        case .listening: return "Compréhension de l'oral"
        case .reading: return "Compréhension des écrits"
        case .language: return "Structures de la langue"
        case .writing: return "Production écrite"
        }
    }

    var symbol: String {
        switch self {
        case .listening: return "ear"
        case .reading: return "doc.text"
        case .language: return "textformat.abc"
        case .writing: return "pencil.line"
        }
    }
}

struct ExamSection: Codable, Hashable {
    let kind: ExamSectionKind
    /// Anweisung, die vor dem Teil angezeigt wird.
    let intro: String
    let tasks: [ExamTask]
}

struct ExamTask: Codable, Hashable {
    /// Situationsbeschreibung auf Deutsch (z. B. "Du hörst eine Durchsage am Bahnhof").
    let context: String?
    /// Vorgelesener französischer Text (nur Hörverstehen). Während der Prüfung unsichtbar.
    let audioScript: String?
    /// Lesetext (nur Leseverstehen) — bleibt bei allen Fragen der Aufgabe sichtbar.
    let passage: String?
    let passageTitle: String?
    let questions: [ExerciseSpec]
}
