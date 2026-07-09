import Foundation

// MARK: - Kursrichtung (Phase 5: Deutsch-Integration)

/// Welche Sprache gelernt wird. `.french` ist der Bestand (Deutschsprachige
/// lernen Französisch), `.german` die Gegenrichtung für Frankophone —
/// Voraussetzung dafür, dass die Tandem-Community auf beiden Seiten echte
/// Lernende hat.
enum CourseDirection: String, Codable, CaseIterable, Identifiable {
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    /// Präfix für persistierte IDs (ReviewState, Zertifikate …) dieser Richtung.
    /// Französisch bleibt unpräfixiert — Bestandsdaten bleiben unverändert gültig.
    var idPrefix: String { self == .german ? "de:" : "" }

    func storageID(_ raw: String) -> String { idPrefix + raw }

    func owns(storageID: String) -> Bool {
        self == .german ? storageID.hasPrefix("de:") : !storageID.contains(":")
    }

    func contentID(fromStorageID id: String) -> String {
        id.hasPrefix("de:") ? String(id.dropFirst(3)) : id
    }

    /// Dateisuffix der richtungseigenen Content-JSONs (course_de.json …).
    var contentSuffix: String { self == .german ? "_de" : "" }

    /// TTS-Stimme der Lernsprache.
    var targetLocaleID: String { self == .german ? "de-DE" : "fr-FR" }

    var certificateSerialPrefix: String { self == .german ? "DE" : "FR" }

    /// Offizielles Vorbild der Niveau-Prüfungen dieser Richtung.
    func examBrand(for level: CEFRLevel) -> String {
        switch self {
        case .german: return "Goethe-Zertifikat"
        case .french: return level >= .c1 ? "DALF" : "DELF"
        }
    }

    var flag: String { self == .german ? "🇩🇪" : "🇫🇷" }

    /// Name der Lernsprache, lokalisiert in der UI-Sprache.
    var targetLanguageName: String {
        self == .german
            ? String(localized: "Deutsch")
            : String(localized: "Französisch")
    }

    /// Name der Muttersprache der Lernenden dieser Richtung.
    var nativeLanguageName: String {
        self == .german
            ? String(localized: "Französisch")
            : String(localized: "Deutsch")
    }
}

/// Entscheidet pro Richtung, welche Seite eines Vokabel-/Satzpaars Lernziel
/// und welche Muttersprache ist. Die JSON-Feldnamen bleiben sprachbezogen
/// (`fr`/`de`) — die Richtung bestimmt, was Prompt und was Lösung ist.
struct LanguagePair {
    let direction: CourseDirection

    func target(_ item: VocabItem) -> String {
        direction == .german ? item.de : item.fr
    }

    func native(_ item: VocabItem) -> String {
        direction == .german ? item.fr : item.de
    }

    func targetExample(_ item: VocabItem) -> String? {
        direction == .german ? item.exampleDE : item.exampleFR
    }

    func nativeExample(_ item: VocabItem) -> String? {
        direction == .german ? item.exampleFR : item.exampleDE
    }

    func targetText(fr: String?, de: String?) -> String? {
        direction == .german ? de : fr
    }

    func nativeText(fr: String?, de: String?) -> String? {
        direction == .german ? fr : de
    }

    /// Lernhinweise sind auf Deutsch für Deutschsprachige verfasst —
    /// im Deutsch-Kurs werden sie nicht angezeigt.
    func note(_ item: VocabItem) -> String? {
        direction == .french ? item.note : nil
    }

    /// Genus-Anzeige nur im Französisch-Kurs; im Deutschen steckt der
    /// Artikel bereits im Wort ("der Herr").
    func genderDetail(_ item: VocabItem) -> String? {
        direction == .french ? item.genderLabel : nil
    }
}

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
        case .a1: return String(localized: "Einstieg")
        case .a2: return String(localized: "Grundlagen")
        case .b1: return String(localized: "Schwelle")
        case .b2: return String(localized: "Fortgeschritten")
        case .c1: return String(localized: "Fachkundig")
        }
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

    var label: String {
        switch self {
        case .noun: return String(localized: "Nomen")
        case .verb: return String(localized: "Verb")
        case .adjective: return String(localized: "Adjektiv")
        case .adverb: return String(localized: "Adverb")
        case .pronoun: return String(localized: "Pronomen")
        case .preposition: return String(localized: "Präposition")
        case .number: return String(localized: "Zahl")
        case .phrase: return String(localized: "Wendung")
        case .interjection: return String(localized: "Ausruf")
        case .conjunction: return String(localized: "Konjunktion")
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
        case "m": return String(localized: "maskulin")
        case "f": return String(localized: "feminin")
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

/// Deutsches Verb für die Gegenrichtung (verbs_de.json). Regelmäßige
/// (schwache) Verben brauchen nur `infinitive`/`fr`/`type`; alles Weitere
/// sind Overrides für starke, gemischte und unregelmäßige Verben.
struct GermanVerbEntry: Codable, Identifiable, Hashable {
    var id: String { infinitive }
    let infinitive: String
    /// Übersetzung in die Sprache der Lernenden (Französisch).
    let fr: String
    /// "weak" | "strong" | "mixed" | "modal" | "irregular"
    let type: String
    /// Trennbares Präfix ("auf" bei aufstehen) — Präsens: "stehe … auf".
    let separablePrefix: String?
    /// Stamm der 2./3. Person Singular bei Vokalwechsel (fahren → "fähr").
    let presentStem23: String?
    /// Sechs Präsensformen (ich, du, er/sie/es, wir, ihr, sie/Sie) —
    /// nur für unregelmäßige Verben (sein, haben, werden, wissen, Modalverben).
    let present: [String]?
    /// Partizip II, falls nicht schwach regelbildbar (ge… t).
    let participle: String?
    /// "sein", falls das Perfekt-Hilfsverb nicht "haben" ist.
    let auxiliary: String?
    /// Sechs Präteritumformen — auf A1 nur für sein/haben/werden/Modalverben.
    let praeteritum: [String]?
    /// Imperativ [du, ihr, Sie], falls unregelmäßig (sei!, iss!).
    let imperative: [String]?
}

struct GermanVerbsFile: Codable {
    let verbs: [GermanVerbEntry]
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

// MARK: - Wortschatz-Pakete

/// Thematisches Vokabelpaket außerhalb des Lektionspfads — wird auf Knopfdruck
/// komplett ins SRS-Training aufgenommen. So wächst der Wortschatz über die
/// Lektionsvokabeln hinaus, ohne dass neue Lektionen nötig sind.
struct VocabPack: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let level: CEFRLevel
    /// SF-Symbol.
    let icon: String?
    let subtitle: String?
    let vocab: [String]
}

struct PacksFile: Codable {
    let packs: [VocabPack]
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
