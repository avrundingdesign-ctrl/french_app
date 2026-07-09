import Foundation

// MARK: - Laufzeit-Übungen

struct MCExercise {
    let instruction: String
    let prompt: String
    /// Sekundärzeile unter dem Prompt (z. B. Wortart oder Übersetzung).
    let promptDetail: String?
    let options: [String]
    let correctIndex: Int
    /// Zusatzinfo fürs Feedback (z. B. Beispielsatz).
    let explanation: String?

    var correctAnswer: String { options[correctIndex] }
}

struct MatchingExercise {
    struct Pair: Identifiable, Hashable {
        let id: String
        let fr: String
        let de: String
    }

    let instruction: String
    let pairs: [Pair]
}

struct TextInputExercise {
    let instruction: String
    /// Satzteil vor der Lücke (kann leer sein).
    let prefix: String
    /// Satzteil nach der Lücke (kann leer sein).
    let suffix: String
    let answer: String
    /// Ebenfalls akzeptierte Antworten (Angleichung, Varianten).
    let altAnswers: [String]
    let hint: String?
    let translation: String?
    /// Vollständige Lösung fürs Feedback.
    let fullSolution: String

    init(
        instruction: String,
        prefix: String,
        suffix: String,
        answer: String,
        altAnswers: [String] = [],
        hint: String?,
        translation: String?,
        fullSolution: String
    ) {
        self.instruction = instruction
        self.prefix = prefix
        self.suffix = suffix
        self.answer = answer
        self.altAnswers = altAnswers
        self.hint = hint
        self.translation = translation
        self.fullSolution = fullSolution
    }

    /// Prüft die Eingabe gegen Haupt- und Alternativantworten; bestes Ergebnis zählt.
    func check(_ input: String) -> AnswerChecker.Result {
        var best: AnswerChecker.Result = .wrong
        for candidate in [answer] + altAnswers {
            switch AnswerChecker.check(input: input, answer: candidate) {
            case .correct:
                return .correct
            case .correctWithAccentHint:
                best = .correctWithAccentHint
            case .wrong:
                break
            }
        }
        return best
    }
}

struct WordOrderExercise {
    let instruction: String
    /// Wörter in korrekter Reihenfolge.
    let tokens: [String]
    /// Deutsche Übersetzung — sagt, welcher Satz zu bilden ist.
    let de: String
}

enum ExerciseKind {
    case multipleChoice(MCExercise)
    case matching(MatchingExercise)
    case textInput(TextInputExercise)
    case wordOrder(WordOrderExercise)
}

/// Stabile Referenz auf einen Übungs-Spec, um Übungen für die
/// Fehlerwiederholung wieder aufbauen zu können.
struct ExerciseRef: Hashable {
    let lessonID: String
    let exerciseIndex: Int
    let subIndex: Int
}

struct RuntimeExercise: Identifiable {
    let ref: ExerciseRef
    let kind: ExerciseKind
    /// Verknüpfte Vokabel (für SRS-Reset bei Fehlern).
    let vocabID: String?
    /// Kurzfassungen fürs Fehlerprotokoll.
    let promptSummary: String
    let answerSummary: String

    var id: String { "\(ref.lessonID)#\(ref.exerciseIndex)#\(ref.subIndex)" }
}

// MARK: - Factory

/// Baut aus den deklarativen Specs des Kursplans konkrete Übungen —
/// inklusive Distraktoren-Auswahl und Konjugator-Anbindung.
struct ExerciseFactory {
    let content: ContentStore

    /// Prompt-/Lösungsseite je Kursrichtung (Deutsch-Kurs: de ist Ziel).
    private var pair: LanguagePair { content.pair }

    func exercises(for lesson: CourseLesson) -> [RuntimeExercise] {
        lesson.exercises.enumerated().flatMap { index, spec in
            build(spec: spec, lesson: lesson, exerciseIndex: index)
        }
    }

    /// Baut eine einzelne Übung anhand ihrer Referenz wieder auf (Fehler üben).
    func exercise(for ref: ExerciseRef) -> RuntimeExercise? {
        guard let lesson = content.lessonByID[ref.lessonID],
              ref.exerciseIndex < lesson.exercises.count
        else { return nil }
        let spec = lesson.exercises[ref.exerciseIndex]
        return build(spec: spec, lesson: lesson, exerciseIndex: ref.exerciseIndex)
            .first { $0.ref.subIndex == ref.subIndex }
    }

    /// Baut eine Übung aus einem freistehenden Spec (Niveau-Prüfungen) — ohne
    /// Lektionskontext. Vokabel-Typen (vocabIntro/vocabProd/matching) brauchen
    /// eine Lektion und sind hier nicht erlaubt.
    func standaloneExercise(spec: ExerciseSpec, ref: ExerciseRef) -> RuntimeExercise? {
        switch spec.type {
        case .cloze:
            guard let text = spec.text, let answer = spec.answer else { return nil }
            return clozeExercise(text: text, answer: answer, spec: spec, ref: ref)
        case .conjugation:
            return conjugationExercise(spec: spec, ref: ref)
        case .wordOrder:
            return wordOrderExercise(spec: spec, ref: ref)
        case .mcSentence:
            return mcSentenceExercise(spec: spec, ref: ref)
        case .translate:
            return translateExercise(spec: spec, ref: ref)
        case .errorCorrection:
            return errorCorrectionExercise(spec: spec, ref: ref)
        case .vocabIntro, .vocabProd, .matching:
            return nil
        }
    }

    // MARK: Aufbau pro Spec-Typ

    private func build(spec: ExerciseSpec, lesson: CourseLesson, exerciseIndex: Int) -> [RuntimeExercise] {
        func ref(_ sub: Int) -> ExerciseRef {
            ExerciseRef(lessonID: lesson.id, exerciseIndex: exerciseIndex, subIndex: sub)
        }

        switch spec.type {
        case .vocabIntro:
            return (spec.vocab ?? []).enumerated().compactMap { sub, vocabID in
                vocabMC(vocabID: vocabID, lesson: lesson, ref: ref(sub), production: false)
            }

        case .vocabProd:
            return (spec.vocab ?? []).enumerated().compactMap { sub, vocabID in
                vocabMC(vocabID: vocabID, lesson: lesson, ref: ref(sub), production: true)
            }

        case .matching:
            let ids = spec.vocab ?? Array(lesson.newVocab.prefix(6))
            let pairs = ids.compactMap { id -> MatchingExercise.Pair? in
                guard let item = content.vocab(id) else { return nil }
                return MatchingExercise.Pair(id: item.id, fr: item.fr, de: item.de)
            }
            guard pairs.count >= 3 else { return [] }
            let exercise = MatchingExercise(instruction: String(localized: "Ordne die Paare zu"), pairs: pairs)
            return [RuntimeExercise(
                ref: ref(0),
                kind: .matching(exercise),
                vocabID: nil,
                promptSummary: "Wortpaare zuordnen",
                answerSummary: pairs.map { "\($0.fr) – \($0.de)" }.joined(separator: ", ")
            )]

        case .cloze:
            guard let text = spec.text, let answer = spec.answer else { return [] }
            return [clozeExercise(text: text, answer: answer, spec: spec, ref: ref(0))]

        case .conjugation:
            guard let exercise = conjugationExercise(spec: spec, ref: ref(0)) else { return [] }
            return [exercise]

        case .wordOrder:
            guard let exercise = wordOrderExercise(spec: spec, ref: ref(0)) else { return [] }
            return [exercise]

        case .mcSentence:
            guard let exercise = mcSentenceExercise(spec: spec, ref: ref(0)) else { return [] }
            return [exercise]

        case .translate:
            guard let exercise = translateExercise(spec: spec, ref: ref(0)) else { return [] }
            return [exercise]

        case .errorCorrection:
            guard let exercise = errorCorrectionExercise(spec: spec, ref: ref(0)) else { return [] }
            return [exercise]
        }
    }

    private func wordOrderExercise(spec: ExerciseSpec, ref: ExerciseRef) -> RuntimeExercise? {
        guard let target = pair.targetText(fr: spec.fr, de: spec.de),
              let native = pair.nativeText(fr: spec.fr, de: spec.de)
        else { return nil }
        let tokens = target.split(separator: " ").map(String.init)
        guard tokens.count >= 3 else { return nil }
        let exercise = WordOrderExercise(
            instruction: content.direction == .german
                ? String(localized: "Bilde den deutschen Satz")
                : String(localized: "Bilde den französischen Satz"),
            tokens: tokens,
            de: native
        )
        return RuntimeExercise(
            ref: ref,
            kind: .wordOrder(exercise),
            vocabID: spec.vocab?.first,
            promptSummary: native,
            answerSummary: target
        )
    }

    private func mcSentenceExercise(spec: ExerciseSpec, ref: ExerciseRef) -> RuntimeExercise? {
        guard let question = spec.question,
              let answer = spec.answer,
              let distractors = spec.distractors,
              !distractors.isEmpty
        else { return nil }
        var options = ([answer] + distractors).shuffled()
        options = dedupe(options)
        guard let correctIndex = options.firstIndex(of: answer) else { return nil }
        let exercise = MCExercise(
            instruction: String(localized: "Wähle die richtige Antwort"),
            prompt: question,
            promptDetail: nil,
            options: options,
            correctIndex: correctIndex,
            explanation: spec.translation
        )
        return RuntimeExercise(
            ref: ref,
            kind: .multipleChoice(exercise),
            vocabID: spec.vocab?.first,
            promptSummary: question,
            answerSummary: answer
        )
    }

    private func translateExercise(spec: ExerciseSpec, ref: ExerciseRef) -> RuntimeExercise? {
        guard let target = pair.targetText(fr: spec.fr, de: spec.de),
              let native = pair.nativeText(fr: spec.fr, de: spec.de)
        else { return nil }
        let exercise = TextInputExercise(
            instruction: content.direction == .german
                ? String(localized: "Übersetze ins Deutsche")
                : String(localized: "Übersetze ins Französische"),
            prefix: "",
            suffix: "",
            answer: target,
            altAnswers: spec.altAnswers ?? [],
            hint: spec.hint,
            translation: native,
            fullSolution: target
        )
        return RuntimeExercise(
            ref: ref,
            kind: .textInput(exercise),
            vocabID: spec.vocab?.first,
            promptSummary: native,
            answerSummary: target
        )
    }

    private func errorCorrectionExercise(spec: ExerciseSpec, ref: ExerciseRef) -> RuntimeExercise? {
        guard let faulty = spec.text,
              let answer = spec.answer,
              let distractors = spec.distractors,
              !distractors.isEmpty
        else { return nil }
        var options = ([answer] + distractors).shuffled()
        options = dedupe(options)
        guard let correctIndex = options.firstIndex(of: answer) else { return nil }
        let exercise = MCExercise(
            instruction: String(localized: "Dieser Satz enthält einen Fehler. Wähle die richtige Version:"),
            prompt: "✗ \(faulty)",
            promptDetail: spec.translation,
            options: options,
            correctIndex: correctIndex,
            explanation: spec.hint
        )
        return RuntimeExercise(
            ref: ref,
            kind: .multipleChoice(exercise),
            vocabID: spec.vocab?.first,
            promptSummary: faulty,
            answerSummary: answer
        )
    }

    private func vocabMC(
        vocabID: String,
        lesson: CourseLesson,
        ref: ExerciseRef,
        production: Bool
    ) -> RuntimeExercise? {
        guard let item = content.vocab(vocabID) else { return nil }
        let distractors = content.distractors(for: item, count: 3, preferring: lesson.newVocab)
        guard distractors.count >= 2 else { return nil }

        let correct = production ? pair.target(item) : pair.native(item)
        var options = ([correct] + distractors.map { production ? pair.target($0) : pair.native($0) }).shuffled()
        options = dedupe(options)
        guard let correctIndex = options.firstIndex(of: correct) else { return nil }

        var detailParts: [String] = [item.pos.label]
        if let genderDetail = pair.genderDetail(item), !production { detailParts.append(genderDetail) }

        var explanation: String?
        if let targetExample = pair.targetExample(item), let nativeExample = pair.nativeExample(item) {
            explanation = "\(targetExample) — \(nativeExample)"
        } else if let note = pair.note(item) {
            explanation = note
        }

        let productionInstruction = content.direction == .german
            ? String(localized: "Wie heißt das auf Deutsch?")
            : String(localized: "Wie heißt das auf Französisch?")
        let exercise = MCExercise(
            instruction: production ? productionInstruction : String(localized: "Was bedeutet das?"),
            prompt: production ? pair.native(item) : pair.target(item),
            promptDetail: production ? nil : detailParts.joined(separator: " · "),
            options: options,
            correctIndex: correctIndex,
            explanation: explanation
        )
        return RuntimeExercise(
            ref: ref,
            kind: .multipleChoice(exercise),
            vocabID: item.id,
            promptSummary: exercise.prompt,
            answerSummary: correct
        )
    }

    private func clozeExercise(text: String, answer: String, spec: ExerciseSpec, ref: ExerciseRef) -> RuntimeExercise {
        let fullSolution = text.replacingOccurrences(of: "___", with: answer)

        if let choices = spec.choices, choices.count >= 2 {
            var options = choices
            if !options.contains(answer) { options.append(answer) }
            options = dedupe(options.shuffled())
            let correctIndex = options.firstIndex(of: answer) ?? 0
            let exercise = MCExercise(
                instruction: String(localized: "Was gehört in die Lücke?"),
                prompt: text,
                promptDetail: spec.translation,
                options: options,
                correctIndex: correctIndex,
                explanation: spec.hint
            )
            return RuntimeExercise(
                ref: ref,
                kind: .multipleChoice(exercise),
                vocabID: spec.vocab?.first,
                promptSummary: text,
                answerSummary: answer
            )
        }

        let parts = text.components(separatedBy: "___")
        let exercise = TextInputExercise(
            instruction: String(localized: "Setze das fehlende Wort ein"),
            prefix: parts.first ?? "",
            suffix: parts.count > 1 ? parts[1] : "",
            answer: answer,
            altAnswers: spec.altAnswers ?? [],
            hint: spec.hint,
            translation: spec.translation,
            fullSolution: fullSolution
        )
        return RuntimeExercise(
            ref: ref,
            kind: .textInput(exercise),
            vocabID: spec.vocab?.first,
            promptSummary: text,
            answerSummary: answer
        )
    }

    private func conjugationExercise(spec: ExerciseSpec, ref: ExerciseRef) -> RuntimeExercise? {
        if content.direction == .german {
            return germanConjugationExercise(spec: spec, ref: ref)
        }
        guard let infinitive = spec.verb,
              let verb = content.conjugator.verb(infinitive),
              let person = spec.person,
              (0...5).contains(person)
        else { return nil }

        let tense = Conjugator.Tense(rawValue: spec.tense ?? "present") ?? .present
        guard let answer = content.conjugator.form(of: verb, tense: tense, person: person) else {
            return nil
        }

        let pronoun: String
        let elided = person == 0 && Conjugator.elidesAfterJe(answer)
        switch person {
        case 0: pronoun = elided ? "j'" : "je"
        case 2: pronoun = "il"
        case 5: pronoun = "ils"
        default: pronoun = Conjugator.tablePronouns[person]
        }

        var prefix = elided ? pronoun : pronoun + " "
        if tense == .subjonctifPresent {
            prefix = (pronoun.hasPrefix("il") ? "qu'" : "que ") + prefix
        }
        let fullSolution = prefix + answer
        // Vokabel-IDs sind ASCII (v_ecouter), Infinitive tragen Akzente (écouter).
        let vocabKey = "v_" + AnswerChecker.stripDiacritics(infinitive)
            .replacingOccurrences(of: "se ", with: "se_")
            .replacingOccurrences(of: "s'", with: "s")
        let vocabID = content.vocabByID[vocabKey] != nil ? vocabKey : nil

        // Angleichung in zusammengesetzten être-Zeiten (inkl. Reflexive):
        // alle Partizip-Varianten akzeptieren.
        var altAnswers: [String] = []
        var hint = spec.hint
        if tense.isCompound, content.conjugator.usesEtreAuxiliary(verb) {
            let head = answer.components(separatedBy: " ").dropLast().joined(separator: " ")
            altAnswers = content.conjugator.participleVariants(of: verb, person: person)
                .map { head + " " + $0 }
                .filter { $0 != answer }
            if hint == nil {
                hint = "Mit être — das Partizip gleicht sich an (alle Formen zählen)."
            }
        }

        let exercise = TextInputExercise(
            instruction: String(localized: "Konjugiere «\(infinitive)» (\(verb.de)) — \(tense.label)"),
            prefix: prefix,
            suffix: "",
            answer: answer,
            altAnswers: altAnswers,
            hint: hint,
            translation: spec.translation,
            fullSolution: fullSolution
        )
        return RuntimeExercise(
            ref: ref,
            kind: .textInput(exercise),
            vocabID: vocabID,
            promptSummary: "\(pronoun) … (\(infinitive), \(tense.label))",
            answerSummary: fullSolution
        )
    }

    /// Konjugationsübung des Deutsch-Kurses: Tempora und Pronomen aus dem
    /// GermanConjugator; Imperativ ohne Subjektpronomen (Personenhinweis in
    /// der Anweisung). Kein Vokabel-Link — die Vokabel-IDs sind FR-basiert.
    private func germanConjugationExercise(spec: ExerciseSpec, ref: ExerciseRef) -> RuntimeExercise? {
        guard let infinitive = spec.verb,
              let verb = content.germanConjugator.verb(infinitive),
              let person = spec.person,
              (0...5).contains(person)
        else { return nil }

        let tense = GermanConjugator.Tense(rawValue: spec.tense ?? "praesens") ?? .praesens
        guard let answer = content.germanConjugator.form(of: verb, tense: tense, person: person) else {
            return nil
        }

        let instruction: String
        let prefix: String
        let pronoun: String
        if tense == .imperativ {
            let personHint = person == 1 ? "du" : person == 4 ? "ihr" : "Sie"
            instruction = String(localized: "Imperativ von „\(infinitive)“ (\(verb.fr)) — \(personHint)-Form")
            prefix = ""
            pronoun = "(\(personHint))"
        } else {
            switch person {
            case 2: pronoun = "er"
            case 5: pronoun = "sie"
            default: pronoun = GermanConjugator.tablePronouns[person]
            }
            instruction = String(localized: "Konjugiere „\(infinitive)“ (\(verb.fr)) — \(tense.label)")
            prefix = pronoun + " "
        }

        let exercise = TextInputExercise(
            instruction: instruction,
            prefix: prefix,
            suffix: "",
            answer: answer,
            altAnswers: spec.altAnswers ?? [],
            hint: spec.hint,
            translation: spec.translation,
            fullSolution: prefix + answer
        )
        return RuntimeExercise(
            ref: ref,
            kind: .textInput(exercise),
            vocabID: nil,
            promptSummary: "\(pronoun) … (\(infinitive), \(tense.label))",
            answerSummary: prefix + answer
        )
    }

    private func dedupe(_ options: [String]) -> [String] {
        var seen = Set<String>()
        return options.filter { seen.insert($0).inserted }
    }
}

// MARK: - Antwortbewertung für Freitext

enum AnswerChecker {
    enum Result {
        case correct
        /// Nur Akzente/Diakritika weichen ab — zählt als richtig, mit Hinweis.
        case correctWithAccentHint
        case wrong
    }

    static func check(input: String, answer: String) -> Result {
        let a = normalize(input)
        let b = normalize(answer)
        if a == b { return .correct }
        if stripDiacritics(a) == stripDiacritics(b) { return .correctWithAccentHint }
        return .wrong
    }

    static func normalize(_ s: String) -> String {
        // Satzzeichen sind für die Bewertung egal (Apostroph und Bindestrich nicht —
        // die sind bedeutungstragend: j'ai, est-ce que).
        let punctuation = CharacterSet(charactersIn: ".,!?;:…«»\"„“”()")
        let cleaned = s.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: punctuation)
            .joined()
        return cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func stripDiacritics(_ s: String) -> String {
        // ß→ss vor dem Falten: Umlaut-/Eszett-Fehler zählen im Deutsch-Kurs
        // wie Akzentfehler im Französischen als „richtig mit Hinweis".
        s.replacingOccurrences(of: "ß", with: "ss")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "œ", with: "oe")
    }
}
