import Foundation

// MARK: - CEFR

enum CEFRLevel: String, Codable, CaseIterable, Identifiable, Comparable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    /// C1 hat (noch) keine Lektionen — nur die Niveau-Prüfung im DALF-Stil.
    case c1 = "C1"

    var id: String { rawValue }

    var sortIndex: Int {
        switch self {
        case .a1: return 0
        case .a2: return 1
        case .b1: return 2
        case .b2: return 3
        case .c1: return 4
        }
    }

    var subtitle: String {
        switch self {
        case .a1: return "Einstieg"
        case .a2: return "Grundlagen"
        case .b1: return "Schwelle"
        case .b2: return "Fortgeschritten"
        case .c1: return "Fachkundig"
        }
    }

    /// Offizielles Vorbild der Niveau-Prüfung: DELF bis B2, DALF ab C1.
    var examBrand: String {
        self >= .c1 ? "DALF" : "DELF"
    }

    static func < (lhs: CEFRLevel, rhs: CEFRLevel) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }
}

// MARK: - Vokabular

enum PartOfSpeech: String, Codable {
    case noun
    case verb
    case adjective
    case adverb
    case pronoun
    case preposition
    case number
    case phrase
    case interjection
    case conjunction

    var germanLabel: String {
        switch self {
        case .noun: return "Nomen"
        case .verb: return "Verb"
        case .adjective: return "Adjektiv"
        case .adverb: return "Adverb"
        case .pronoun: return "Pronomen"
        case .preposition: return "Präposition"
        case .number: return "Zahl"
        case .phrase: return "Wendung"
        case .interjection: return "Ausruf"
        case .conjunction: return "Konjunktion"
        }
    }
}

struct VocabItem: Codable, Identifiable, Hashable {
    let id: String
    /// Französische Form, bei Nomen inklusive Artikel (z. B. "le pain", "l'eau").
    let fr: String
    let de: String
    let pos: PartOfSpeech
    /// "m" oder "f" bei Nomen.
    let gender: String?
    /// Optionaler Lernhinweis (z. B. Aussprache-Falle, Registerhinweis).
    let note: String?
    let exampleFR: String?
    let exampleDE: String?

    var genderLabel: String? {
        switch gender {
        case "m": return "maskulin"
        case "f": return "feminin"
        default: return nil
        }
    }
}

struct VocabularyFile: Codable {
    let vocabulary: [VocabItem]
}

// MARK: - Verben

struct VerbEntry: Codable, Identifiable, Hashable {
    var id: String { infinitive }
    let infinitive: String
    let de: String
    /// 1 = -er, 2 = -ir (-issant), 3 = unregelmäßig (Formen aus Tabelle).
    let group: Int
    /// Sechs Präsensformen (je, tu, il/elle, nous, vous, ils/elles) — nur für Gruppe 3.
    let present: [String]?
    /// Participe passé — nur nötig, wenn unregelmäßig.
    let participle: String?
    /// "être", falls das Hilfsverb nicht "avoir" ist.
    let auxiliary: String?
    /// Unregelmäßiger Futur-simple-Stamm (être → "ser", avoir → "aur" …).
    let futurStem: String?
    /// Sechs Subjonctif-présent-Formen — nur für Verben mit eigenem
    /// Subjonctif-Stamm (être, avoir, aller, faire, pouvoir, vouloir, savoir).
    let subjonctif: [String]?
}

struct VerbsFile: Codable {
    let verbs: [VerbEntry]
}

// MARK: - Grammatik

struct ExamplePair: Codable, Hashable {
    let fr: String
    let de: String
}

struct GrammarRule: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let level: CEFRLevel
    /// Erklärung auf Deutsch, einfaches Markdown (fett via **…**).
    let explanation: String
    let examples: [ExamplePair]
    /// Typischer Fehler deutschsprachiger Lernender.
    let typicalMistake: String?
    /// Infinitive, deren Konjugationstabellen auf der Detailseite gezeigt werden.
    let verbTables: [String]?
}

struct GrammarFile: Codable {
    let rules: [GrammarRule]
}

// MARK: - Hörtraining

/// Wortpaar, das sich nur in einem Laut unterscheidet (rue/roue) —
/// Hörunterscheidung für Laute, die Deutschsprachigen schwerfallen.
struct MinimalPair: Codable, Hashable {
    let a: String
    let b: String
    let deA: String
    let deB: String
    /// Kurzbezeichnung des Lautkontrasts, z. B. "u – ou".
    let contrast: String
}

struct ListeningFile: Codable {
    let minimalPairs: [MinimalPair]
}

// MARK: - Kursplan

struct CourseFile: Codable {
    let units: [CourseUnit]
}

struct CourseUnit: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let level: CEFRLevel
    /// SF-Symbol für die Einheit.
    let icon: String?
    let lessons: [CourseLesson]
}

struct CourseLesson: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    /// IDs der verknüpften Grammatikregeln.
    let grammar: [String]?
    /// IDs der in dieser Lektion neu eingeführten Vokabeln (wandern in den SRS-Pool).
    let newVocab: [String]
    let exercises: [ExerciseSpec]
}

// MARK: - Übungs-Specs (deklarativ im JSON)

enum ExerciseSpecType: String, Codable {
    /// Erkennen FR→DE als Multiple Choice; `vocab` = Liste von Vokabel-IDs (je eine Übung).
    case vocabIntro
    /// Produktion DE→FR als Multiple Choice; `vocab` = Liste von Vokabel-IDs.
    case vocabProd
    /// Wortpaare zuordnen; `vocab` = 4–6 Vokabel-IDs (fehlt es, nimmt die Factory die Lektionsvokabeln).
    case matching
    /// Lückentext. `text` enthält "___", `answer` die Lösung. Mit `choices` als Auswahl, sonst Freitext.
    case cloze
    /// Verbform eingeben. `verb` (Infinitiv), `person` (0–5), `tense` ("present" | "passeCompose" | "futurProche").
    case conjugation
    /// Wörter in die richtige Reihenfolge bringen. `fr` = Zielsatz, `de` = Übersetzung.
    case wordOrder
    /// Satzbezogenes Multiple Choice. `question`, `answer`, `distractors`, optional `translation`.
    case mcSentence
    /// Produktion DE→FR als Freitext. `de` = Aufgabe, `fr` = Lösung, optional `altAnswers`.
    case translate
    /// Fehlerkorrektur: `text` = fehlerhafter Satz, `answer` = korrigierte Version,
    /// `distractors` = weitere falsche Korrekturen, optional `translation`.
    case errorCorrection
}

struct ExerciseSpec: Codable, Hashable {
    let type: ExerciseSpecType
    let vocab: [String]?
    let text: String?
    let answer: String?
    let translation: String?
    let hint: String?
    let choices: [String]?
    let verb: String?
    let person: Int?
    let tense: String?
    let question: String?
    let distractors: [String]?
    let fr: String?
    let de: String?
    /// Zusätzlich akzeptierte Antworten (z. B. Angleichungsvarianten, Synonyme).
    let altAnswers: [String]?

    init(
        type: ExerciseSpecType,
        vocab: [String]? = nil,
        text: String? = nil,
        answer: String? = nil,
        translation: String? = nil,
        hint: String? = nil,
        choices: [String]? = nil,
        verb: String? = nil,
        person: Int? = nil,
        tense: String? = nil,
        question: String? = nil,
        distractors: [String]? = nil,
        fr: String? = nil,
        de: String? = nil,
        altAnswers: [String]? = nil
    ) {
        self.type = type
        self.vocab = vocab
        self.text = text
        self.answer = answer
        self.translation = translation
        self.hint = hint
        self.choices = choices
        self.verb = verb
        self.person = person
        self.tense = tense
        self.question = question
        self.distractors = distractors
        self.fr = fr
        self.de = de
        self.altAnswers = altAnswers
    }
}
