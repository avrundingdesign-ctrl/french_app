import Foundation

/// Regelbasierter Konjugator für den Deutsch-Kurs (Gegenstück zum
/// französischen `Conjugator`). Schwache Verben werden vollständig aus dem
/// Stamm generiert; starke, gemischte und unregelmäßige Verben liefern
/// Overrides aus verbs_de.json. Alles selbst verfasst — keine GPL-Quellen.
///
/// A1: Präsens, Perfekt, Präteritum (nur sein/haben/werden und Modalverben,
/// per Datentabelle), Imperativ (du/ihr/Sie).
/// A2: Futur (werden + Infinitiv) und Reflexivverben ("sich waschen" →
/// "wasche mich"), erkannt am Infinitiv-Präfix "sich ".
struct GermanConjugator {
    enum Tense: String, CaseIterable, Identifiable {
        case praesens
        case perfekt
        case praeteritum
        case plusquamperfekt
        case futur
        case konjunktiv2
        case imperativ

        var id: String { rawValue }

        var label: String {
            switch self {
            case .praesens: return String(localized: "Präsens")
            case .perfekt: return String(localized: "Perfekt")
            case .praeteritum: return String(localized: "Präteritum")
            case .plusquamperfekt: return String(localized: "Plusquamperfekt")
            case .futur: return String(localized: "Futur")
            case .konjunktiv2: return String(localized: "Konjunktiv II")
            case .imperativ: return String(localized: "Imperativ")
            }
        }
    }

    /// Reflexivpronomen (Akkusativ) je Person: wasche mich, wäschst dich …
    static let reflexivePronouns = ["mich", "dich", "sich", "uns", "euch", "sich"]

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
    /// nachgestelltem Präfix ("stehe auf"), bei Reflexiven inklusive Pronomen
    /// ("wasche mich"). nil, wenn das Tempus für dieses Verb nicht verfügbar
    /// ist (z. B. Präteritum außerhalb der Tabelle).
    func form(of verb: GermanVerbEntry, tense: Tense, person: Int) -> String? {
        guard (0...5).contains(person) else { return nil }
        let reflexive = isReflexive(verb) ? Self.reflexivePronouns[person] : nil

        switch tense {
        case .praesens:
            guard let finite = presentFinite(verb, person: person) else { return nil }
            // wasche mich · ziehe mich an
            let withReflexive = reflexive.map { "\(finite) \($0)" } ?? finite
            return withPrefix(withReflexive, verb: verb)
        case .perfekt:
            guard let participle = participle(of: verb),
                  let aux = auxiliaryForm(of: verb, person: person)
            else { return nil }
            // habe mich gewaschen
            if let reflexive { return "\(aux) \(reflexive) \(participle)" }
            return "\(aux) \(participle)"
        case .praeteritum:
            guard let forms = praeteritumForms(verb) else { return nil }
            let withReflexive = reflexive.map { "\(forms[person]) \($0)" } ?? forms[person]
            return withPrefix(withReflexive, verb: verb)
        case .plusquamperfekt:
            // hatte gearbeitet · war aufgestanden · hatte mich gewaschen
            guard let participle = participle(of: verb),
                  let aux = auxiliaryPraeteritumForm(of: verb, person: person)
            else { return nil }
            if let reflexive { return "\(aux) \(reflexive) \(participle)" }
            return "\(aux) \(participle)"
        case .futur:
            // werde arbeiten · werde mich waschen · werde aufstehen
            guard let werden = werdenForm(person: person) else { return nil }
            let infinitive = bareInfinitive(verb)
            if let reflexive { return "\(werden) \(reflexive) \(infinitive)" }
            return "\(werden) \(infinitive)"
        case .konjunktiv2:
            if let table = verb.konjunktivII, table.count == 6 {
                let withReflexive = reflexive.map { "\(table[person]) \($0)" } ?? table[person]
                return withPrefix(withReflexive, verb: verb)
            }
            // Modalverben bilden nie die würde-Form ("würde möchten" wäre falsch) —
            // ohne eigene Tabelle gibt es für sie kein Konjunktiv II.
            guard verb.type != "modal" else { return nil }
            // würde arbeiten · würde mich waschen · würde aufstehen
            guard let wuerde = byInfinitive["werden"]?.konjunktivII, wuerde.count == 6 else { return nil }
            let infinitive = bareInfinitive(verb)
            if let reflexive { return "\(wuerde[person]) \(reflexive) \(infinitive)" }
            return "\(wuerde[person]) \(infinitive)"
        case .imperativ:
            guard Self.imperativePersons.contains(person),
                  let finite = imperativeFinite(verb, person: person)
            else { return nil }
            // wasch dich! · waschen Sie sich! · zieh dich an!
            let withReflexive = reflexive.map { "\(finite) \($0)" } ?? finite
            return withPrefix(withReflexive, verb: verb)
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

    /// "sich waschen" → reflexiv; Pronomen kommt zur Laufzeit dazu.
    private func isReflexive(_ verb: GermanVerbEntry) -> Bool {
        verb.infinitive.hasPrefix("sich ")
    }

    /// Infinitiv ohne "sich " ("sich waschen" → "waschen").
    private func bareInfinitive(_ verb: GermanVerbEntry) -> String {
        isReflexive(verb) ? String(verb.infinitive.dropFirst(5)) : verb.infinitive
    }

    /// Infinitiv ohne "sich " und ohne trennbares Präfix ("sich anziehen" → "ziehen").
    private func baseInfinitive(_ verb: GermanVerbEntry) -> String {
        let bare = bareInfinitive(verb)
        guard let prefix = verb.separablePrefix, bare.hasPrefix(prefix) else {
            return bare
        }
        return String(bare.dropFirst(prefix.count))
    }

    /// Präsens von "werden" fürs Futur — aus der eigenen Verbtabelle.
    private func werdenForm(person: Int) -> String? {
        guard let werden = byInfinitive["werden"], let forms = werden.present, forms.count == 6 else {
            return nil
        }
        return forms[person]
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
        guard let prefix = verb.separablePrefix, bareInfinitive(verb).hasPrefix(prefix) else {
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
        if let prefix = verb.separablePrefix, bareInfinitive(verb).hasPrefix(prefix) {
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

    // MARK: - Präteritum

    /// Sechs Präteritumformen, gleich welche Verbklasse: Tabellen-Override
    /// (irregulär/Modal) > Ablaut-Stamm (stark/gemischt) > Regel aus dem
    /// Infinitivstamm (schwach).
    private func praeteritumForms(_ verb: GermanVerbEntry) -> [String]? {
        if let table = verb.praeteritum, table.count == 6 { return table }
        if let stem = verb.praeteritumStem {
            switch verb.type {
            case "strong": return strongPraeteritumForms(stem: stem)
            case "mixed": return weakPraeteritumForms(stem: stem)
            default: return nil
            }
        }
        guard verb.type == "weak" else { return nil }
        let base = baseInfinitive(verb)
        return weakPraeteritumForms(stem: stem(ofBase: base))
    }

    /// Starke Endungen: ich/er ohne Endung, du -st/-est, wir/sie -en,
    /// ihr -t/-et — dieselben Kontraktions-/Epenthese-Regeln wie im Präsens
    /// (z. B. "fandest" bei d-Stämmen, "last" bei s-Stämmen).
    private func strongPraeteritumForms(stem: String) -> [String] {
        let du = contractsS(stem) ? stem + "t" : stem + (needsEpenthesis(stem) ? "est" : "st")
        let ihr = needsEpenthesis(stem) ? stem + "et" : stem + "t"
        return [stem, du, stem, stem + "en", ihr, stem + "en"]
    }

    /// Schwache Endungen -te/-test/-te/-ten/-tet/-ten, mit Epenthese-e bei
    /// Stämmen auf t/d bzw. Nasal nach Konsonant (arbeitete, öffnete).
    private func weakPraeteritumForms(stem: String) -> [String] {
        let core = stem + (needsEpenthesis(stem) ? "e" : "")
        return [core + "te", core + "test", core + "te", core + "ten", core + "tet", core + "ten"]
    }

    private func auxiliaryPraeteritumForm(of verb: GermanVerbEntry, person: Int) -> String? {
        let auxInfinitive = verb.auxiliary ?? "haben"
        guard let aux = byInfinitive[auxInfinitive], let forms = praeteritumForms(aux) else {
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
