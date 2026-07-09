import Foundation

/// Baut Hörtraining-Übungen aus vorhandenem Content: Dictée und Hör-Lückentext
/// aus den Beispielsätzen (Grammatik + Vokabeln, nach Niveau gefiltert),
/// Hörunterscheidung aus den kuratierten Minimal-Paaren.
struct ListeningTrainer {
    struct Sentence: Hashable {
        /// Satz in der Lernsprache (wird vorgelesen und getippt).
        let target: String
        /// Übersetzung in der Muttersprache (Feedback).
        let native: String
        let level: CEFRLevel
    }

    enum Mode: String, CaseIterable, Identifiable {
        case dictation
        case cloze
        case minimalPairs

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dictation: return String(localized: "Diktat")
            case .cloze: return String(localized: "Hör-Lückentext")
            case .minimalPairs: return String(localized: "Wortpaare")
            }
        }

        var symbol: String {
            switch self {
            case .dictation: return "waveform"
            case .cloze: return "text.badge.checkmark"
            case .minimalPairs: return "ear"
            }
        }

        var description: String {
            switch self {
            case .dictation: return String(localized: "Schreibe ganze Sätze nach Gehör — der Klassiker des Sprachunterrichts.")
            case .cloze: return String(localized: "Höre den Satz und ergänze das fehlende Wort.")
            case .minimalPairs: return String(localized: "Trainiere Laute, die ähnlich klingen.")
            }
        }

        /// Nur die Satz-Modi brauchen eine Niveau-Auswahl.
        var usesLevel: Bool { self != .minimalPairs }
    }

    struct Exercise: Identifiable {
        let id: String
        /// Text, den die Sprachausgabe vorliest.
        let audio: String
        let kind: ExerciseKind
        /// Deutsche Übersetzung fürs Feedback nach der Antwort.
        let translation: String?
    }

    /// Nur mit iOS-Tastatur + Akzentleiste tippbare Sätze kommen in den Pool
    /// (inkl. deutscher Umlaute/ß für die Gegenrichtung).
    static let typeable = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789 éèêàçùâîôûëïöüœäß'-"
    )

    let content: ContentStore
    let sentences: [Sentence]

    init(content: ContentStore = .shared) {
        self.content = content
        let pair = content.pair

        var seen = Set<String>()
        var pool: [Sentence] = []
        func add(_ target: String?, _ native: String?, _ level: CEFRLevel?) {
            guard let target, let native, let level else { return }
            let normalized = AnswerChecker.normalize(target)
            let wordCount = normalized.split(separator: " ").count
            guard (3...12).contains(wordCount),
                  normalized.unicodeScalars.allSatisfy({ Self.typeable.contains($0) }),
                  seen.insert(normalized).inserted
            else { return }
            pool.append(Sentence(target: target, native: native, level: level))
        }

        for rule in content.grammarRules {
            for example in rule.examples {
                add(
                    pair.targetText(fr: example.fr, de: example.de),
                    pair.nativeText(fr: example.fr, de: example.de),
                    rule.level
                )
            }
        }
        for item in content.vocabulary {
            add(pair.targetExample(item), pair.nativeExample(item), content.vocabLevelByID[item.id])
        }
        self.sentences = pool
    }

    func sentences(upTo level: CEFRLevel) -> [Sentence] {
        sentences.filter { $0.level <= level }
    }

    // MARK: - Übungsgeneratoren

    func dictationExercises(upTo level: CEFRLevel, count: Int) -> [Exercise] {
        sentences(upTo: level).shuffled().prefix(count).enumerated().map { index, sentence in
            let input = TextInputExercise(
                instruction: String(localized: "Diktat: Schreibe den Satz, den du hörst"),
                prefix: "",
                suffix: "",
                answer: sentence.target,
                hint: nil,
                translation: nil,
                fullSolution: sentence.target
            )
            return Exercise(
                id: "dictation#\(index)",
                audio: sentence.target,
                kind: .textInput(input),
                translation: sentence.native
            )
        }
    }

    func clozeExercises(upTo level: CEFRLevel, count: Int) -> [Exercise] {
        var result: [Exercise] = []
        for (index, sentence) in sentences(upTo: level).shuffled().enumerated() {
            guard result.count < count else { break }
            guard let split = Self.gapSplit(sentence.target) else { continue }
            let input = TextInputExercise(
                instruction: String(localized: "Höre den Satz und setze das fehlende Wort ein"),
                prefix: split.prefix,
                suffix: split.suffix,
                answer: split.word,
                hint: nil,
                translation: nil,
                fullSolution: sentence.target
            )
            result.append(Exercise(
                id: "cloze#\(index)",
                audio: sentence.target,
                kind: .textInput(input),
                translation: sentence.native
            ))
        }
        return result
    }

    func minimalPairExercises(count: Int) -> [Exercise] {
        // deA/deB sind per Konvention Glossen in der Muttersprache der
        // Lernenden (listening_de.json trägt dort französische Übersetzungen).
        content.minimalPairs.shuffled().prefix(count).enumerated().map { index, pair in
            let firstIsSpoken = Bool.random()
            let spoken = firstIsSpoken ? pair.a : pair.b
            let mc = MCExercise(
                instruction: String(localized: "Welches Wort hörst du?"),
                prompt: String(localized: "Kontrast: \(pair.contrast)"),
                promptDetail: String(localized: "Die beiden Wörter klingen ähnlich — höre genau hin."),
                options: ["\(pair.a) — \(pair.deA)", "\(pair.b) — \(pair.deB)"],
                correctIndex: firstIsSpoken ? 0 : 1,
                explanation: "\(pair.a) (\(pair.deA)) ↔ \(pair.b) (\(pair.deB))"
            )
            return Exercise(
                id: "pair#\(index)",
                audio: spoken,
                kind: .multipleChoice(mc),
                translation: nil
            )
        }
    }

    func exercises(mode: Mode, upTo level: CEFRLevel, count: Int) -> [Exercise] {
        switch mode {
        case .dictation: return dictationExercises(upTo: level, count: count)
        case .cloze: return clozeExercises(upTo: level, count: count)
        case .minimalPairs: return minimalPairExercises(count: count)
        }
    }

    /// Zerlegt einen Satz in Präfix, Lückenwort und Suffix. Lückenwort ist das
    /// längste reine Wort ab 4 Buchstaben; Satzzeichen bleiben in Präfix/Suffix,
    /// sodass prefix + word + suffix wieder den Originalsatz ergibt.
    static func gapSplit(_ sentence: String) -> (prefix: String, word: String, suffix: String)? {
        let tokens = sentence.components(separatedBy: " ")
        var best: (index: Int, word: String)?
        for (index, token) in tokens.enumerated() {
            let word = token.trimmingCharacters(in: CharacterSet.letters.inverted)
            guard word.count >= 4, word.allSatisfy(\.isLetter) else { continue }
            if best == nil || word.count > best!.word.count {
                best = (index, word)
            }
        }
        guard let best, let inner = tokens[best.index].range(of: best.word) else { return nil }

        let token = tokens[best.index]
        var prefix = tokens[..<best.index].joined(separator: " ")
        if !prefix.isEmpty { prefix += " " }
        prefix += String(token[..<inner.lowerBound])
        var suffix = String(token[inner.upperBound...])
        let rest = tokens[(best.index + 1)...].joined(separator: " ")
        if !rest.isEmpty { suffix += " " + rest }
        return (prefix, best.word, suffix)
    }
}
