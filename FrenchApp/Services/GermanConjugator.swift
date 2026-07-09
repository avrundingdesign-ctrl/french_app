import Foundation

/// Regelbasierter Konjugator für den Deutsch-Kurs (Gegenstück zum
/// französischen `Conjugator`). Schwache Verben werden vollständig aus dem
/// Stamm generiert; starke, gemischte und unregelmäßige Verben liefern
/// Overrides aus verbs_de.json. Alles selbst verfasst — keine GPL-Quellen.
///
/// A1-Umfang: Präsens, Perfekt, Präteritum (nur sein/haben/werden und
/// Modalverben, per Datentabelle), Imperativ (du/ihr/Sie).
struct GermanConjugator {
    enum Tense: String, CaseIterable, Identifiable {
        case praesens
        case perfekt
        case praeteritum
        case imperativ

        var id: String { rawValue }

        var label: String {
            switch self {
            case .praesens: return String(localized: "Präsens")
            case .perfekt: return String(localized: "Perfekt")
            case .praeteritum: return String(localized: "Präteritum")
            case .imperativ: return String(localized: "Imperativ")
            }
        }
    }

    static let tablePronouns = ["ich", "du", "er/sie/es", "wir", "ihr", "sie/Sie"]
    /// Imperativ existiert nur für du (1), ihr (4) und Sie (5).
    static let imperativePersons: Set<Int> = [1, 4, 5]

    /// Untrennbare Präfixe — Partizip II ohne "ge-" (besucht, verkauft).
    private static let inseparablePrefixes = ["be", "ge", "er", "ver", "zer", "ent", "emp", "miss"]

    let verbs: [GermanVerbEntry]
    private let byInfinitive: [String: GermanVerbEntry]

    init(verbs: [GermanVerbEntry]) {
        self.verbs = verbs
        self.byInfinitive = Dictionary(uniqueKeysWithValues: verbs.map { ($0.infinitive, $0) })
    }

    func verb(_ infinitive: String) -> GermanVerbEntry? {
        byInfinitive[infinitive]
    }

    // MARK: - Öffentliche API (Spiegel des französischen Conjugators)

    /// Finite Form ohne Subjektpronomen; bei trennbaren Verben inklusive
    /// nachgestelltem Präfix ("stehe auf"). nil, wenn das Tempus für dieses
    /// Verb nicht verfügbar ist (z. B. Präteritum außerhalb der Tabelle).
    func form(of verb: GermanVerbEntry, tense: Tense, person: Int) -> String? {
        guard (0...5).contains(person) else { return nil }
        switch tense {
        case .praesens:
            guard let finite = presentFinite(verb, person: person) else { return nil }
            return withPrefix(finite, verb: verb)
        case .perfekt:
            guard let participle = participle(of: verb),
                  let aux = auxiliaryForm(of: verb, person: person)
            else { return nil }
            return "\(aux) \(participle)"
        case .praeteritum:
            guard let forms = verb.praeteritum, forms.count == 6 else { return nil }
            return withPrefix(forms[person], verb: verb)
        case .imperativ:
            guard Self.imperativePersons.contains(person),
                  let finite = imperativeFinite(verb, person: person)
            else { return nil }
            return withPrefix(finite, verb: verb)
        }
    }

    /// Konjugationstabelle fürs UI. Imperativ liefert nur die drei
    /// existierenden Formen (du, ihr, Sie).
    func table(for verb: GermanVerbEntry, tense: Tense) -> [(pronoun: String, form: String)] {
        if tense == .imperativ {
            return [(1, "(du)"), (4, "(ihr)"), (5, "(Sie)")].compactMap { person, pronoun in
                form(of: verb, tense: tense, person: person).map { (pronoun, $0) }
            }
        }
        return (0...5).compactMap { person in
            form(of: verb, tense: tense, person: person).map { (Self.tablePronouns[person], $0) }
        }
    }

    /// Tempora, für die dieses Verb Formen liefert (fürs Tabellen-UI).
    func availableTenses(for verb: GermanVerbEntry) -> [Tense] {
        Tense.allCases.filter { tense in
            let probe = tense == .imperativ ? 1 : 0
            return form(of: verb, tense: tense, person: probe) != nil
        }
    }

    // MARK: - Stammlogik

    /// Infinitiv ohne trennbares Präfix ("aufstehen" → "stehen").
    private func baseInfinitive(_ verb: GermanVerbEntry) -> String {
        guard let prefix = verb.separablePrefix, verb.infinitive.hasPrefix(prefix) else {
            return verb.infinitive
        }
        return String(verb.infinitive.dropFirst(prefix.count))
    }

    private func stem(ofBase base: String) -> String {
        if base.hasSuffix("en") { return String(base.dropLast(2)) }
        if base.hasSuffix("n") { return String(base.dropLast(1)) }
        return base
    }

    /// e-Epenthese: arbeitest, öffnest, atmest — Stamm auf t/d oder auf
    /// m/n nach Konsonant (außer l, r, h, m, n).
    private func needsEpenthesis(_ stem: String) -> Bool {
        guard let last = stem.last else { return false }
        if last == "t" || last == "d" { return true }
        if last == "m" || last == "n" {
            guard let previous = stem.dropLast().last else { return false }
            let blockers: Set<Character> = ["l", "r", "h", "m", "n"]
            return !previous.isVowel && !blockers.contains(previous)
        }
        return false
    }

    /// s-Kontraktion in der 2. Person: du reist, du heißt, du tanzt.
    private func contractsS(_ stem: String) -> Bool {
        stem.hasSuffix("s") || stem.hasSuffix("ß") || stem.hasSuffix("x") || stem.hasSuffix("z")
    }

    private func withPrefix(_ finite: String, verb: GermanVerbEntry) -> String {
        guard let prefix = verb.separablePrefix, verb.infinitive.hasPrefix(prefix) else {
            return finite
        }
        return "\(finite) \(prefix)"
    }

    // MARK: - Präsens

    private func presentFinite(_ verb: GermanVerbEntry, person: Int) -> String? {
        if let forms = verb.present {
            guard forms.count == 6 else { return nil }
            return forms[person]
        }
        let base = baseInfinitive(verb)
        let stem = stem(ofBase: base)

        switch person {
        case 0:
            return stem + "e"
        case 1:
            // Starker Stammwechsel (fähr, iss, lies) — ohne e-Epenthese:
            // du hältst, du lädst; s-Kontraktion greift weiter (du isst).
            if let stem23 = verb.presentStem23 {
                return stem23 + (contractsS(stem23) ? "t" : "st")
            }
            if contractsS(stem) { return stem + "t" }
            return stem + (needsEpenthesis(stem) ? "est" : "st")
        case 2:
            if let stem23 = verb.presentStem23 {
                // er hält (kein doppeltes t), aber er lädt.
                return stem23.hasSuffix("t") ? stem23 : stem23 + "t"
            }
            return stem + (needsEpenthesis(stem) ? "et" : "t")
        case 3, 5:
            return base
        case 4:
            return stem + (needsEpenthesis(stem) ? "et" : "t")
        default:
            return nil
        }
    }

    // MARK: - Perfekt

    /// Vollständiges Partizip II (bei trennbaren Verben inkl. Präfix:
    /// "aufgestanden", "eingekauft"). nil, wenn nicht regelbildbar und
    /// keine Tabellenform vorliegt (starke Verben brauchen `participle`).
    func participle(of verb: GermanVerbEntry) -> String? {
        if let explicit = verb.participle { return explicit }
        // Nur schwache Verben sind regelbildbar.
        guard verb.type == "weak" else { return nil }
        let base = baseInfinitive(verb)
        let stem = stem(ofBase: base)
        let ending = needsEpenthesis(stem) ? "et" : "t"

        let core: String
        if base.hasSuffix("ieren") {
            core = stem + "t"                                  // studiert
        } else if Self.inseparablePrefixes.contains(where: { base.hasPrefix($0) }) {
            core = stem + ending                               // besucht, erklärt
        } else {
            core = "ge" + stem + ending                        // gekauft, gearbeitet
        }
        if let prefix = verb.separablePrefix, verb.infinitive.hasPrefix(prefix) {
            return prefix + core                               // eingekauft
        }
        return core
    }

    private func auxiliaryForm(of verb: GermanVerbEntry, person: Int) -> String? {
        let auxInfinitive = verb.auxiliary ?? "haben"
        guard let aux = byInfinitive[auxInfinitive], let forms = aux.present, forms.count == 6 else {
            return nil
        }
        return forms[person]
    }

    // MARK: - Imperativ

    private func imperativeFinite(_ verb: GermanVerbEntry, person: Int) -> String? {
        let base = baseInfinitive(verb)
        if let explicit = verb.imperative {
            guard explicit.count == 3 else { return nil }
            switch person {
            case 1: return explicit[0]
            case 4: return explicit[1]
            case 5: return explicit[2]
            default: return nil
            }
        }
        // Verben mit eigener Präsenstabelle (sein, Modalverben) haben ohne
        // Tabellenform keinen regelbildbaren Imperativ.
        guard verb.present == nil else { return nil }
        let stem = stem(ofBase: base)
        switch person {
        case 1:
            // fahr! (a→ä-Wechsel entfällt im Imperativ), arbeite!, öffne!
            return stem + (needsEpenthesis(stem) ? "e" : "")
        case 4:
            return stem + (needsEpenthesis(stem) ? "et" : "t")
        case 5:
            return "\(base) Sie"
        default:
            return nil
        }
    }
}

private extension Character {
    var isVowel: Bool {
        "aeiouäöü".contains(lowercased())
    }
}
