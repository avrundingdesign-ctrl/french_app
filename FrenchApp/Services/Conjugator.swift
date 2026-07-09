import Foundation

/// Regelbasierter französischer Konjugator.
///
/// Gruppe 1 (-er) und Gruppe 2 (-ir/-issant) werden generiert
/// (Stamm = Infinitiv minus Endung, plus Orthografie-Regeln),
/// Gruppe 3 kommt vollständig aus der gebündelten Ausnahmentabelle (`verbs.json`).
///
/// Tempora: Präsens, Imparfait, Subjonctif présent, Conditionnel présent,
/// Futur simple, Futur proche sowie die zusammengesetzten Zeiten Passé composé,
/// Plus-que-parfait, Futur antérieur und Conditionnel passé — inklusive
/// être-Hilfsverb, Angleichung und Reflexivverben (je me suis levé).
/// Alle Daten sind selbst verfasst — keine Verbiste-Ableitung (Lizenz, siehe SPEC §5).
struct Conjugator {
    enum Tense: String, CaseIterable {
        case present
        case imparfait
        case passeCompose
        case plusQueParfait
        case futurProche
        case futurSimple
        case futurAnterieur
        case conditionnel
        case conditionnelPasse
        case subjonctifPresent

        var label: String {
            switch self {
            case .present: return "Präsens"
            case .imparfait: return "Imparfait"
            case .passeCompose: return "Passé composé"
            case .plusQueParfait: return "Plus-que-parfait"
            case .futurProche: return "Futur proche"
            case .futurSimple: return "Futur simple"
            case .futurAnterieur: return "Futur antérieur"
            case .conditionnel: return "Conditionnel"
            case .conditionnelPasse: return "Conditionnel passé"
            case .subjonctifPresent: return "Subjonctif"
            }
        }

        /// Zusammengesetzte Zeiten: Hilfsverb + Participe passé.
        var isCompound: Bool {
            switch self {
            case .passeCompose, .plusQueParfait, .futurAnterieur, .conditionnelPasse:
                return true
            default:
                return false
            }
        }

        /// Tempus, in dem das Hilfsverb steht.
        var auxiliaryTense: Tense? {
            switch self {
            case .passeCompose: return .present
            case .plusQueParfait: return .imparfait
            case .futurAnterieur: return .futurSimple
            case .conditionnelPasse: return .conditionnel
            default: return nil
            }
        }
    }

    /// Anzeige-Pronomen für Tabellen.
    static let tablePronouns = ["je", "tu", "il/elle", "nous", "vous", "ils/elles"]

    private let verbsByInfinitive: [String: VerbEntry]

    /// -er-Verben mit Stammwechsel e → è (acheter → j'achète) —
    /// der Wechsel gilt auch im Futur simple (j'achèterai).
    private static let eGraveVerbs: Set<String> = [
        "acheter", "lever", "promener", "emmener", "amener", "peser",
    ]

    /// -er-Verben mit Stammwechsel é → è (préférer → je préfère) —
    /// im Futur simple bleibt das é erhalten (je préférerai).
    private static let accentGraveVerbs: Set<String> = [
        "préférer", "espérer", "répéter", "compléter", "posséder", "protéger",
    ]

    /// -er-Verben mit Konsonantverdopplung (appeler → j'appelle, j'appellerai).
    private static let doublingVerbs: Set<String> = ["appeler", "jeter", "rappeler", "rejeter"]

    /// -yer-Verben mit y → i (payer → je paie, je paierai).
    private static let yToIVerbs: Set<String> = ["payer", "essayer", "employer", "envoyer", "nettoyer"]

    /// -ir-Verben mit -er-Präsensendungen (offrir → j'offre, ouvrir → j'ouvre).
    private static let erLikeIrVerbs: Set<String> = ["offrir", "ouvrir", "découvrir", "souffrir"]

    init(verbs: [VerbEntry]) {
        self.verbsByInfinitive = Dictionary(uniqueKeysWithValues: verbs.map { ($0.infinitive, $0) })
    }

    func verb(_ infinitive: String) -> VerbEntry? {
        verbsByInfinitive[infinitive]
    }

    // MARK: - Reflexive Verben

    /// "se lever" → true, "s'habiller" → true.
    static func isReflexive(_ infinitive: String) -> Bool {
        infinitive.hasPrefix("se ") || infinitive.hasPrefix("s'")
    }

    /// "se lever" → "lever", "s'habiller" → "habiller".
    static func baseInfinitive(_ infinitive: String) -> String {
        if infinitive.hasPrefix("se ") { return String(infinitive.dropFirst(3)) }
        if infinitive.hasPrefix("s'") { return String(infinitive.dropFirst(2)) }
        return infinitive
    }

    /// Reflexivpronomen je/tu/il/nous/vous/ils — mit Elision vor Vokal (m', t', s').
    static func reflexivePronoun(person: Int, before form: String) -> String {
        let pronouns = ["me", "te", "se", "nous", "vous", "se"]
        let pronoun = pronouns[person]
        if ["me", "te", "se"].contains(pronoun), startsWithVowelSound(form) {
            return String(pronoun.first!) + "'"
        }
        return pronoun + " "
    }

    static func startsWithVowelSound(_ form: String) -> Bool {
        guard let first = form.lowercased().first else { return false }
        return "aeiouâàéèêëîïôöûüh".contains(first)
    }

    // MARK: - Präsens

    /// Sechs Präsensformen des Grundverbs (ohne Pronomen, ohne Reflexivpronomen).
    func basePresentForms(of verb: VerbEntry) -> [String] {
        if let irregular = verb.present {
            return irregular
        }
        let base = Self.baseInfinitive(verb.infinitive)
        if Self.erLikeIrVerbs.contains(base) {
            // offrir → offr- mit -er-Endungen: offre, offres, offre …
            let stem = String(base.dropLast(2))
            return ["e", "es", "e", "ons", "ez", "ent"].map { stem + $0 }
        }
        switch verb.group {
        case 1:
            return Self.firstGroupPresent(infinitive: base)
        case 2:
            let stem = String(base.dropLast(2))
            return [stem + "is", stem + "is", stem + "it", stem + "issons", stem + "issez", stem + "issent"]
        default:
            // Gruppe 3 ohne Tabelleneintrag wäre ein Inhaltsfehler — wird von Tests abgefangen.
            return []
        }
    }

    /// Präsensformen inklusive Reflexivpronomen ("me lève", "t'habilles" …).
    func presentForms(of verb: VerbEntry) -> [String] {
        let forms = basePresentForms(of: verb)
        guard Self.isReflexive(verb.infinitive), forms.count == 6 else { return forms }
        return forms.enumerated().map { person, form in
            Self.reflexivePronoun(person: person, before: form) + form
        }
    }

    static func firstGroupPresent(infinitive: String) -> [String] {
        let stem = String(infinitive.dropLast(2))
        let endings = ["e", "es", "e", "ons", "ez", "ent"]
        var stems = Array(repeating: stem, count: 6)

        // je/tu/il/ils nutzen bei Stammwechsel-Verben den angepassten Stamm.
        let softIndices = [0, 1, 2, 5]
        if eGraveVerbs.contains(infinitive) || accentGraveVerbs.contains(infinitive) {
            let changed = graveStem(stem)
            for i in softIndices { stems[i] = changed }
        } else if doublingVerbs.contains(infinitive), let last = stem.last {
            let doubled = stem + String(last)
            for i in softIndices { stems[i] = doubled }
        } else if yToIVerbs.contains(infinitive) {
            let changed = String(stem.dropLast()) + "i"
            for i in softIndices { stems[i] = changed }
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

    // MARK: - Imparfait

    /// Imparfait-Stamm = nous-Form des Präsens ohne -ons; Ausnahme: être → ét-.
    func imparfaitStem(of verb: VerbEntry) -> String? {
        if Self.baseInfinitive(verb.infinitive) == "être" { return "ét" }
        let forms = basePresentForms(of: verb)
        guard forms.count == 6, forms[3].hasSuffix("ons") else { return nil }
        return String(forms[3].dropLast(3))
    }

    func imparfaitForms(of verb: VerbEntry) -> [String]? {
        guard let stem = imparfaitStem(of: verb) else { return nil }
        let endings = ["ais", "ais", "ait", "ions", "iez", "aient"]
        return endings.map { ending in
            var s = stem
            // mangeons → nous mangions (kein e vor i), commençons → nous commencions.
            if ending.hasPrefix("i") {
                if s.hasSuffix("ge") { s = String(s.dropLast()) }
                if s.hasSuffix("ç") { s = String(s.dropLast()) + "c" }
            }
            return s + ending
        }
    }

    // MARK: - Subjonctif présent

    /// Regelbildung: Stamm der ils-Form + -e/-es/-e/-ent, nous/vous = Imparfait.
    /// Verben mit eigenem Subjonctif (être, avoir, aller …) kommen aus der Tabelle.
    func subjonctifForms(of verb: VerbEntry) -> [String]? {
        if let irregular = verb.subjonctif {
            return irregular
        }
        let present = basePresentForms(of: verb)
        guard present.count == 6, present[5].hasSuffix("ent"),
              let imparfait = imparfaitForms(of: verb)
        else { return nil }
        let stem = String(present[5].dropLast(3))
        return [stem + "e", stem + "es", stem + "e", imparfait[3], imparfait[4], stem + "ent"]
    }

    // MARK: - Futur simple & Conditionnel

    /// Futur-Stamm: unregelmäßig aus der Tabelle (ser-, aur-, ir- …),
    /// sonst Infinitiv (bei -re ohne Schluss-e; Stammwechsel-Verben behalten è/ll/i).
    func futurStem(of verb: VerbEntry) -> String {
        if let irregular = verb.futurStem { return irregular }
        let base = Self.baseInfinitive(verb.infinitive)
        var stem = base
        if stem.hasSuffix("re") { stem = String(stem.dropLast()) }

        if Self.eGraveVerbs.contains(base) {
            // acheter → achèter-
            let inner = Self.graveStem(String(base.dropLast(2)))
            stem = inner + "er"
        } else if Self.doublingVerbs.contains(base), let last = base.dropLast(2).last {
            // appeler → appeller-
            stem = String(base.dropLast(2)) + String(last) + "er"
        } else if Self.yToIVerbs.contains(base) {
            // payer → paier-
            stem = String(base.dropLast(3)) + "ier"
        }
        return stem
    }

    func futurSimpleForms(of verb: VerbEntry) -> [String] {
        let stem = futurStem(of: verb)
        return ["ai", "as", "a", "ons", "ez", "ont"].map { stem + $0 }
    }

    /// Conditionnel présent: Futur-Stamm + Imparfait-Endungen.
    func conditionnelForms(of verb: VerbEntry) -> [String] {
        let stem = futurStem(of: verb)
        return ["ais", "ais", "ait", "ions", "iez", "aient"].map { stem + $0 }
    }

    // MARK: - Participe passé & Hilfsverb

    func participle(of verb: VerbEntry) -> String {
        if let p = verb.participle { return p }
        let base = Self.baseInfinitive(verb.infinitive)
        let stem = String(base.dropLast(2))
        switch verb.group {
        case 1: return stem + "é"
        case 2: return stem + "i"
        default: return stem
        }
    }

    /// Braucht dieses Verb in zusammengesetzten Zeiten être (inkl. Reflexive)?
    func usesEtreAuxiliary(_ verb: VerbEntry) -> Bool {
        verb.auxiliary == "être" || Self.isReflexive(verb.infinitive)
    }

    /// Angleichungs-Varianten des Partizips für être-Verben (allé, allée, allés, allées),
    /// eingeschränkt auf die für die Person plausiblen Formen.
    func participleVariants(of verb: VerbEntry, person: Int) -> [String] {
        let p = participle(of: verb)
        switch person {
        case 0, 1, 2: return [p, p + "e"]
        case 3, 5: return [p + "s", p + "es"]
        default: return [p, p + "e", p + "s", p + "es"] // vous: Sg./Pl., m/f
        }
    }

    // MARK: - Formen für Übungen & Tabellen

    /// Verbform (ohne Subjektpronomen) für Tempus + Person (0–5).
    /// Reflexivpronomen ist enthalten ("me lève", "me suis levé").
    /// Zusammengesetzte être-Zeiten liefern die maskuline Grundform
    /// ("suis allé", "sommes allés") — Varianten via `participleVariants`.
    func form(of verb: VerbEntry, tense: Tense, person: Int) -> String? {
        guard (0...5).contains(person) else { return nil }
        let reflexive = Self.isReflexive(verb.infinitive)

        func withReflexive(_ form: String) -> String {
            reflexive ? Self.reflexivePronoun(person: person, before: form) + form : form
        }

        if tense.isCompound {
            return compoundForm(of: verb, tense: tense, person: person)
        }

        switch tense {
        case .present:
            let forms = basePresentForms(of: verb)
            return forms.count == 6 ? withReflexive(forms[person]) : nil

        case .imparfait:
            guard let forms = imparfaitForms(of: verb) else { return nil }
            return withReflexive(forms[person])

        case .subjonctifPresent:
            guard let forms = subjonctifForms(of: verb), forms.count == 6 else { return nil }
            return withReflexive(forms[person])

        case .futurProche:
            guard let aller = verbsByInfinitive["aller"], let aux = aller.present?[person] else { return nil }
            if reflexive {
                let base = Self.baseInfinitive(verb.infinitive)
                let pronoun = Self.reflexivePronoun(person: person, before: base)
                return aux + " " + pronoun + base
            }
            return aux + " " + verb.infinitive

        case .futurSimple:
            let forms = futurSimpleForms(of: verb)
            guard forms.count == 6, !forms[person].isEmpty else { return nil }
            return withReflexive(forms[person])

        case .conditionnel:
            let forms = conditionnelForms(of: verb)
            guard forms.count == 6, !forms[person].isEmpty else { return nil }
            return withReflexive(forms[person])

        default:
            return nil
        }
    }

    /// Zusammengesetzte Zeiten: Hilfsverb im passenden Tempus + Participe passé.
    /// Reflexiv: Pronomen + être ("me suis levé").
    private func compoundForm(of verb: VerbEntry, tense: Tense, person: Int) -> String? {
        guard let auxTense = tense.auxiliaryTense else { return nil }
        let reflexive = Self.isReflexive(verb.infinitive)
        let needsEtre = usesEtreAuxiliary(verb)

        guard let auxVerb = verbsByInfinitive[needsEtre ? "être" : "avoir"],
              let auxForm = form(of: auxVerb, tense: auxTense, person: person)
        else { return nil }

        var agreed = participle(of: verb)
        if needsEtre, [3, 5].contains(person) {
            agreed += "s"
        }

        if reflexive {
            let pronoun = Self.reflexivePronoun(person: person, before: auxForm)
            return pronoun + auxForm + " " + agreed
        }
        return auxForm + " " + agreed
    }

    /// "je" wird vor Vokal oder stummem h zu "j'" (j'aime, j'habite, j'ai mangé).
    static func elidesAfterJe(_ form: String) -> Bool {
        startsWithVowelSound(form)
    }

    /// Subjektpronomen fürs Prompt/Tabelle — Subjonctif bekommt "que" davor.
    static func displayPronoun(person: Int, form: String, tense: Tense) -> String {
        let base: String
        if person == 0 {
            base = elidesAfterJe(form) ? "j'" : "je"
        } else {
            base = tablePronouns[person]
        }
        guard tense == .subjonctifPresent else { return base }
        if base.hasPrefix("il") || base.hasPrefix("ils") {
            return "qu'" + base
        }
        return "que " + base
    }

    /// Konjugationstabelle fürs UI: [(Pronomen, Form)] mit Elision.
    /// Zusammengesetzte être-Zeiten zeigen die Angleichung: "suis allé(e)".
    func table(for verb: VerbEntry, tense: Tense = .present) -> [(pronoun: String, form: String)] {
        (0...5).compactMap { person in
            guard var f = form(of: verb, tense: tense, person: person) else { return nil }
            if tense.isCompound, usesEtreAuxiliary(verb) {
                switch person {
                case 3, 5: f = String(f.dropLast()) + "(e)s" // sommes allés → sommes allé(e)s
                case 4: f += "(e)(s)"                        // êtes allé(e)(s)
                default: f += "(e)"                          // suis allé(e)
                }
            }
            return (Self.displayPronoun(person: person, form: f, tense: tense), f)
        }
    }
}
