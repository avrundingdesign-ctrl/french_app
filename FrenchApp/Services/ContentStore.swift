import Foundation

/// Lädt die gebündelten, read-only Inhaltsdaten (Vokabeln, Verben, Grammatik, Kursplan).
///
/// Bewusst von SwiftData getrennt gehalten (Spec §8): Inhalte sind statisch und
/// werden einmal beim Start dekodiert; nur der Nutzerfortschritt ist veränderlich.
final class ContentStore {
    /// Der Französisch-Kurs (Bestand) — Alias auf den gecachten Store.
    static let shared: ContentStore = store(for: .french)

    private static var cache: [CourseDirection: ContentStore] = [:]
    private static let cacheLock = NSLock()

    /// Gecachter Store pro Kursrichtung. Beide Richtungen teilen sich
    /// vocabulary.json; alle übrigen Dateien tragen das Richtungssuffix.
    static func store(for direction: CourseDirection) -> ContentStore {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let existing = cache[direction] { return existing }
        do {
            let store = try ContentStore(bundle: .main, direction: direction)
            cache[direction] = store
            return store
        } catch {
            fatalError("Inhaltsdaten (\(direction.rawValue)) konnten nicht geladen werden: \(error)")
        }
    }

    let direction: CourseDirection
    var pair: LanguagePair { LanguagePair(direction: direction) }

    let vocabulary: [VocabItem]
    let vocabByID: [String: VocabItem]
    let verbs: [VerbEntry]
    let germanVerbs: [GermanVerbEntry]
    let grammarRules: [GrammarRule]
    let grammarByID: [String: GrammarRule]
    let units: [CourseUnit]
    let exams: [ExamDefinition]
    let examByLevel: [CEFRLevel: ExamDefinition]
    let minimalPairs: [MinimalPair]
    let packs: [VocabPack]
    let challenges: [ChallengeChapter]
    let challengeByLevel: [CEFRLevel: ChallengeChapter]
    let conjugator: Conjugator
    let germanConjugator: GermanConjugator

    /// Alle Lektionen in Kurs-Reihenfolge (über Einheiten und Niveaus hinweg).
    let orderedLessons: [CourseLesson]
    let lessonByID: [String: CourseLesson]
    private let lessonIndexByID: [String: Int]
    let unitByLessonID: [String: CourseUnit]
    /// Niveau, auf dem eine Vokabel eingeführt wird (erste Lektion zählt).
    let vocabLevelByID: [String: CEFRLevel]

    init(bundle: Bundle, direction: CourseDirection = .french) throws {
        self.direction = direction
        let decoder = JSONDecoder()
        let suffix = direction.contentSuffix

        func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw NSError(
                    domain: "ContentStore", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "\(name).json fehlt im Bundle"]
                )
            }
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        }

        // Vokabeln sind fr/de-Paare und damit richtungsneutral — geteilt.
        self.vocabulary = try load("vocabulary", as: VocabularyFile.self).vocabulary
        // Verbdaten sind sprachspezifisch: jede Richtung lädt nur ihre eigenen.
        if direction == .french {
            self.verbs = try load("verbs", as: VerbsFile.self).verbs
            self.germanVerbs = []
        } else {
            self.verbs = []
            self.germanVerbs = try load("verbs_de", as: GermanVerbsFile.self).verbs
        }
        self.grammarRules = try load("grammar" + suffix, as: GrammarFile.self).rules
        self.units = try load("course" + suffix, as: CourseFile.self).units
        self.exams = try load("exams" + suffix, as: ExamFile.self).exams
        self.examByLevel = Dictionary(uniqueKeysWithValues: exams.map { ($0.level, $0) })
        self.minimalPairs = try load("listening" + suffix, as: ListeningFile.self).minimalPairs
        self.packs = try load("packs" + suffix, as: PacksFile.self).packs
        self.challenges = try load("challenges" + suffix, as: ChallengesFile.self).challenges
        self.challengeByLevel = Dictionary(uniqueKeysWithValues: challenges.map { ($0.level, $0) })

        self.vocabByID = Dictionary(uniqueKeysWithValues: vocabulary.map { ($0.id, $0) })
        self.grammarByID = Dictionary(uniqueKeysWithValues: grammarRules.map { ($0.id, $0) })
        self.conjugator = Conjugator(verbs: verbs)
        self.germanConjugator = GermanConjugator(verbs: germanVerbs)

        var ordered: [CourseLesson] = []
        var byID: [String: CourseLesson] = [:]
        var unitLookup: [String: CourseUnit] = [:]
        var vocabLevels: [String: CEFRLevel] = [:]
        // Stabil nach Niveau sortieren (JSON-Reihenfolge innerhalb eines Niveaus bleibt).
        let sortedUnits = units.enumerated()
            .sorted { ($0.element.level.sortIndex, $0.offset) < ($1.element.level.sortIndex, $1.offset) }
            .map(\.element)
        for unit in sortedUnits {
            for lesson in unit.lessons {
                ordered.append(lesson)
                byID[lesson.id] = lesson
                unitLookup[lesson.id] = unit
                for vocabID in lesson.newVocab where vocabLevels[vocabID] == nil {
                    vocabLevels[vocabID] = unit.level
                }
            }
        }
        // Paket-Vokabeln bekommen das Paket-Niveau (Lektionen haben Vorrang).
        for pack in packs {
            for vocabID in pack.vocab where vocabLevels[vocabID] == nil {
                vocabLevels[vocabID] = pack.level
            }
        }

        self.orderedLessons = ordered
        self.lessonByID = byID
        self.unitByLessonID = unitLookup
        self.vocabLevelByID = vocabLevels
        self.lessonIndexByID = Dictionary(
            uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset) }
        )
    }

    // MARK: - Abfragen

    func vocab(_ id: String) -> VocabItem? { vocabByID[id] }

    // MARK: SRS-IDs (richtungsgetrennt)

    /// ID, unter der eine Vokabel dieser Richtung im SRS persistiert wird
    /// (Deutsch-Kurs: "de:v_bonjour"; Französisch-Kurs unverändert).
    func srsID(for vocabID: String) -> String {
        direction.storageID(vocabID)
    }

    /// Löst eine persistierte SRS-ID zur Vokabel auf — nil, wenn die Karte
    /// zur jeweils anderen Kursrichtung gehört (filtert Fremdkarten aus).
    func vocab(forReviewID id: String) -> VocabItem? {
        guard direction.owns(storageID: id) else { return nil }
        return vocabByID[direction.contentID(fromStorageID: id)]
    }

    func lesson(before lesson: CourseLesson) -> CourseLesson? {
        guard let index = lessonIndexByID[lesson.id], index > 0 else { return nil }
        return orderedLessons[index - 1]
    }

    func lesson(after lesson: CourseLesson) -> CourseLesson? {
        guard let index = lessonIndexByID[lesson.id], index + 1 < orderedLessons.count else { return nil }
        return orderedLessons[index + 1]
    }

    func lessons(for level: CEFRLevel) -> [CourseLesson] {
        units.filter { $0.level == level }.flatMap(\.lessons)
    }

    var levels: [CEFRLevel] {
        Array(Set(units.map(\.level))).sorted()
    }

    /// Lektionen, die eine Grammatikregel behandeln.
    func lessons(covering grammarID: String) -> [CourseLesson] {
        orderedLessons.filter { ($0.grammar ?? []).contains(grammarID) }
    }

    /// Distraktoren für Multiple Choice: bevorzugt gleiche Wortart, niemals das Wort selbst
    /// und keine Duplikate der richtigen Antwort.
    func distractors(for item: VocabItem, count: Int, preferring pool: [String]) -> [VocabItem] {
        let poolItems = pool.compactMap { vocabByID[$0] }
        var candidates = poolItems.filter { $0.id != item.id && $0.de != item.de && $0.fr != item.fr }
        let samePOS = candidates.filter { $0.pos == item.pos }
        if samePOS.count >= count {
            candidates = samePOS
        }
        var result = Array(candidates.shuffled().prefix(count))

        if result.count < count {
            let existing = Set(result.map(\.id) + [item.id])
            let global = vocabulary.filter {
                !existing.contains($0.id) && $0.de != item.de && $0.fr != item.fr && $0.pos == item.pos
            }
            result.append(contentsOf: global.shuffled().prefix(count - result.count))
        }
        if result.count < count {
            let existing = Set(result.map(\.id) + [item.id])
            let global = vocabulary.filter { !existing.contains($0.id) && $0.de != item.de && $0.fr != item.fr }
            result.append(contentsOf: global.shuffled().prefix(count - result.count))
        }
        return result
    }
}
