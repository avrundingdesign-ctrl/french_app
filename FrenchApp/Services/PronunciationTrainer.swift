import Foundation

// MARK: - Bewertung

/// Bewertet eine Sprechübung: Wie nah kommt das, was die Spracherkennung
/// verstanden hat, dem Zielwort/-satz? Reine Textlogik, testbar ohne Mikrofon.
///
/// Die Idee: Wer gut ausspricht, wird von der Erkennung richtig verstanden.
/// Das misst keine Phonetik im engeren Sinn, ist aber ein ehrliches,
/// offline-fähiges Signal — und dieselbe Methode, die viele Lern-Apps nutzen.
enum PronunciationScorer {
    struct WordFeedback: Identifiable, Hashable {
        /// Wort in Originalschreibweise des Zieltextes.
        let word: String
        let matched: Bool
        /// Position im Zieltext — Wörter können mehrfach vorkommen.
        let index: Int

        var id: Int { index }
    }

    enum Verdict {
        case excellent
        case good
        case tryAgain

        var title: String {
            switch self {
            case .excellent: return String(localized: "Ausgezeichnet!")
            case .good: return String(localized: "Gut verständlich")
            case .tryAgain: return String(localized: "Noch einmal versuchen")
            }
        }

        var symbol: String {
            switch self {
            case .excellent: return "star.circle.fill"
            case .good: return "hand.thumbsup.circle.fill"
            case .tryAgain: return "arrow.counterclockwise.circle.fill"
            }
        }
    }

    struct Assessment {
        /// 0…1 — Ähnlichkeit zwischen Ziel und Verstandenem.
        let score: Double
        let words: [WordFeedback]
        /// Was die Erkennung verstanden hat (Anzeige).
        let transcript: String

        var verdict: Verdict {
            if score >= 0.85 { return .excellent }
            if score >= 0.6 { return .good }
            return .tryAgain
        }

        /// Zählt in der Session-Bilanz als gelungen.
        var isPass: Bool { score >= 0.6 }
    }

    /// Ab dieser Wort-Ähnlichkeit gilt ein einzelnes Wort als getroffen.
    static let wordMatchThreshold = 0.7

    static func assess(target: String, transcript: String) -> Assessment {
        let normalizedTarget = normalize(target)
        let normalizedTranscript = normalize(transcript)

        let score = normalizedTranscript.isEmpty
            ? 0
            : similarity(normalizedTarget, normalizedTranscript)

        // Wort-Feedback: jedes Zielwort gegen die verstandenen Wörter,
        // jedes verstandene Wort zählt nur einmal (greedy in Satzreihenfolge).
        let targetWords = target.split(separator: " ").map(String.init)
        var remaining = normalizedTranscript.split(separator: " ").map(String.init)
        let words = targetWords.enumerated().map { index, word in
            let normalizedWord = normalize(word)
            // Reine Satzzeichen-Tokens („—") sind nichts zum Aussprechen.
            guard !normalizedWord.isEmpty else {
                return WordFeedback(word: word, matched: true, index: index)
            }
            let best = remaining.enumerated()
                .map { ($0.offset, similarity(normalizedWord, $0.element)) }
                .max { $0.1 < $1.1 }
            if let best, best.1 >= wordMatchThreshold {
                remaining.remove(at: best.0)
                return WordFeedback(word: word, matched: true, index: index)
            }
            return WordFeedback(word: word, matched: false, index: index)
        }

        return Assessment(score: score, words: words, transcript: transcript)
    }

    /// Zeichen-Ähnlichkeit zweier (normalisierter) Strings: 1 − Levenshtein/maxLänge.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let maxLength = max(a.count, b.count)
        guard maxLength > 0 else { return 1 }
        return 1 - Double(levenshtein(a, b)) / Double(maxLength)
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }

        var previous = Array(0...bChars.count)
        var current = [Int](repeating: 0, count: bChars.count + 1)

        for i in 1...aChars.count {
            current[0] = i
            for j in 1...bChars.count {
                let substitution = previous[j - 1] + (aChars[i - 1] == bChars[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[bChars.count]
    }

    /// Kleinschreibung, ohne Satzzeichen — Akzente bleiben (die Erkennung
    /// liefert korrekt akzentuierte Wörter, das Ziel trägt sie auch).
    static func normalize(_ s: String) -> String {
        AnswerChecker.normalize(s)
    }
}

// MARK: - Übungspool

/// Baut Sprechübungen aus vorhandenem Content: Vokabeln (inkl. Artikel)
/// und die Beispielsätze des Hörtrainings, nach Niveau gefiltert.
struct PronunciationTrainer {
    struct Item: Identifiable, Hashable {
        /// Zieltext in der Lernsprache — wird vorgesprochen und nachgesprochen.
        let text: String
        /// Übersetzung in der Muttersprache.
        let translation: String
        let level: CEFRLevel

        var id: String { text }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case words
        case sentences

        var id: String { rawValue }

        var title: String {
            switch self {
            case .words: return String(localized: "Wörter nachsprechen")
            case .sentences: return String(localized: "Sätze nachsprechen")
            }
        }

        var symbol: String {
            switch self {
            case .words: return "mic"
            case .sentences: return "mic.badge.plus"
            }
        }

        var description: String {
            switch self {
            case .words: return String(localized: "Sprich einzelne Wörter nach — die App bewertet deine Aussprache.")
            case .sentences: return String(localized: "Ganze Sätze flüssig aussprechen — die Königsdisziplin.")
            }
        }
    }

    let content: ContentStore

    init(content: ContentStore = .shared) {
        self.content = content
    }

    func items(mode: Mode, upTo level: CEFRLevel, count: Int) -> [Item] {
        switch mode {
        case .words: return Array(wordItems(upTo: level).shuffled().prefix(count))
        case .sentences: return Array(sentenceItems(upTo: level).shuffled().prefix(count))
        }
    }

    func wordItems(upTo level: CEFRLevel) -> [Item] {
        let pair = content.pair
        var seen = Set<String>()
        return content.vocabulary.compactMap { item in
            guard let itemLevel = content.vocabLevelByID[item.id], itemLevel <= level else { return nil }
            let text = pair.target(item)
            // Nur echte Wörter/Wendungen, keine langen Einträge mit Zusätzen.
            guard text.split(separator: " ").count <= 3, seen.insert(text).inserted else { return nil }
            return Item(text: text, translation: pair.native(item), level: itemLevel)
        }
    }

    func sentenceItems(upTo level: CEFRLevel) -> [Item] {
        ListeningTrainer(content: content).sentences(upTo: level).map {
            Item(text: $0.target, translation: $0.native, level: $0.level)
        }
    }
}
