import Foundation

/// Regelbasierter französischer Konjugator.
///
/// Gruppe 1 (-er) und Gruppe 2 (-ir/-issant) werden generiert
/// (Stamm = Infinitiv minus Endung, plus Orthografie-Regeln),
/// Gruppe 3 kommt vollständig aus der gebündelten Ausnahmentabelle (`verbs.json`).
/// Alle Daten sind selbst verfasst — keine Verbiste-Ableitung (Lizenz, siehe SPEC §5).
struct Conjugator {
    enum Tense: String {
        case present
        case passeCompose
        case futurProche

        var germanLabel: String {
            switch self {
            case .present: return "Präsens"
            case .passeCompose: return "Passé composé"
            case .futurProche: return "Futur proche"
            }
        }
    }

    /// Anzeige-Pronomen für Tabellen.
    static let tablePronouns = ["je", "tu", "il/elle", "nous", "vous", "ils/elles"]

    private let verbsByInfinitive: [String: VerbEntry]

    /// -er-Verben mit Stammwechsel e/é → è (acheter → j'achète, préférer → je préfère).
    private static let graveStemVerbs: Set<String> = [
        "acheter", "lever", "promener", "emmener", "peser", "amener",
        "préférer", "espérer", "répéter", "compléter", "posséder",
    ]

    /// -er-Verben mit Konsonantverdopplung (appeler → j'appelle, jeter → je jette).
    private static let doublingVerbs: Set<String> = ["appeler", "jeter", "rappeler", "rejeter"]

    init(verbs: [VerbEntry]) {
        self.verbsByInfinitive = Dictionary(uniqueKeysWithValues: verbs.map { ($0.infinitive, $0) })
    }

    func verb(_ infinitive: String) -> VerbEntry? {
        verbsByInfinitive[infinitive]
    }

    // MARK: - Präsens

    /// Sechs Präsensformen (ohne Pronomen): je, tu, il/elle, nous, vous, ils/elles.
    func presentForms(of verb: VerbEntry) -> [String] {
        if let irregular = verb.present {
            return irregular
        }
        switch verb.group {
        case 1:
            return Self.firstGroupPresent(infinitive: verb.infinitive)
        case 2:
            let stem = String(verb.infinitive.dropLast(2))
            return [stem + "is", stem + "is", stem + "it", stem + "issons", stem + "issez", stem + "issent"]
        default:
            // Gruppe 3 ohne Tabelleneintrag wäre ein Inhaltsfehler — wird von Tests abgefangen.
            return []
        }
    }

    static func firstGroupPresent(infinitive: String) -> [String] {
        let stem = String(infinitive.dropLast(2))
        let endings = ["e", "es", "e", "ons", "ez", "ent"]
        var stems = Array(repeating: stem, count: 6)

        // je/tu/il/ils nutzen bei Stammwechsel-Verben den angepassten Stamm.
        let softIndices = [0, 1, 2, 5]
        if graveStemVerbs.contains(infinitive) {
            let changed = graveStem(stem)
            for i in softIndices { stems[i] = changed }
        } else if doublingVerbs.contains(infinitive), let last = stem.last {
            let doubled = stem + String(last)
            for i in softIndices { stems[i] = doubled }
        }

        // Orthografie in der nous-Form: manger → mangeons, commencer → commençons.
        if infinitive.hasSuffix("ger") {
            stems[3] = stem + "e"
        } else if infinitive.hasSuffix("cer") {
            stems[3] = String(stem.dropLast()) + "ç"
        }

        return zip(stems, endings).map(+)
    }

    /// Ersetzt das letzte e/é vor dem Stammende durch è (achet → achèt, préfér → préfèr).
    private static func graveStem(_ stem: String) -> String {
        var chars = Array(stem)
        for i in stride(from: chars.count - 1, through: 0, by: -1) {
            if chars[i] == "e" || chars[i] == "é" {
                chars[i] = "è"
                break
            }
        }
        return String(chars)
    }

    // MARK: - Participe passé & Hilfsverb

    func participle(of verb: VerbEntry) -> String {
        if let p = verb.participle { return p }
        let stem = String(verb.infinitive.dropLast(2))
        switch verb.group {
        case 1: return stem + "é"
        case 2: return stem + "i"
        default: return stem
        }
    }

    // MARK: - Formen für Übungen & Tabellen

    /// Verbform (ohne Pronomen) für Tempus + Person (0–5).
    /// Passé composé: "ai mangé" · Futur proche: "vais manger".
    func form(of verb: VerbEntry, tense: Tense, person: Int) -> String? {
        guard (0...5).contains(person) else { return nil }
        switch tense {
        case .present:
            let forms = presentForms(of: verb)
            return forms.count == 6 ? forms[person] : nil
        case .passeCompose:
            guard verb.auxiliary != "être",
                  let avoir = verbsByInfinitive["avoir"],
                  let aux = avoir.present?[person]
            else { return nil }
            return aux + " " + participle(of: verb)
        case .futurProche:
            guard let aller = verbsByInfinitive["aller"],
                  let aux = aller.present?[person]
            else { return nil }
            return aux + " " + verb.infinitive
        }
    }

    /// Vollständige Zeile mit Pronomen und Elision: "j'aime", "il/elle parle".
    func displayForm(pronounIndex: Int, form: String) -> String {
        let pronoun = Self.tablePronouns[pronounIndex]
        if pronounIndex == 0 {
            return Self.elidesAfterJe(form) ? "j'" + form : "je " + form
        }
        return pronoun + " " + form
    }

    /// "je" wird vor Vokal oder stummem h zu "j'" (j'aime, j'habite).
    static func elidesAfterJe(_ form: String) -> Bool {
        guard let first = form.lowercased().first else { return false }
        return "aeiouâàéèêëîïôöûüh".contains(first)
    }

    /// Konjugationstabelle fürs UI: [(Pronomen, Form)] mit Elision.
    func table(for verb: VerbEntry, tense: Tense = .present) -> [(pronoun: String, form: String)] {
        (0...5).compactMap { person in
            guard let f = form(of: verb, tense: tense, person: person) else { return nil }
            if person == 0 {
                return Self.elidesAfterJe(f) ? ("j'", f) : ("je", f)
            }
            return (Self.tablePronouns[person], f)
        }
    }
}
