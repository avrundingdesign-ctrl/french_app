import Foundation
import SwiftData

// MARK: - SM-2-Zustand pro Vokabel

@Model
final class ReviewState {
    @Attribute(.unique) var vocabID: String
    var easeFactor: Double
    /// Zähler erfolgreicher Wiederholungen in Folge.
    var repetitions: Int
    /// Tage bis zur nächsten Fälligkeit.
    var interval: Int
    var nextReview: Date
    var introducedAt: Date
    /// Erstes Review überhaupt — Karten ohne Wert gelten als "neu".
    var firstReviewedAt: Date?
    var lastReviewedAt: Date?
    /// Wie oft eine bereits gelernte Karte wieder vergessen wurde.
    var lapses: Int
    var totalReviews: Int

    init(vocabID: String, now: Date = .now) {
        self.vocabID = vocabID
        self.easeFactor = SM2.startEaseFactor
        self.repetitions = 0
        self.interval = 0
        self.nextReview = Calendar.current.startOfDay(for: now)
        self.introducedAt = now
        self.firstReviewedAt = nil
        self.lastReviewedAt = nil
        self.lapses = 0
        self.totalReviews = 0
    }

    var isNew: Bool { firstReviewedAt == nil }

    /// "Gefestigt" im Anki-Sinn: Intervall ≥ 21 Tage.
    var isMature: Bool { interval >= 21 }

    func isDue(at date: Date) -> Bool {
        !isNew && nextReview <= date
    }
}

// MARK: - Lektionsfortschritt

@Model
final class LessonProgress {
    @Attribute(.unique) var lessonID: String
    var completedAt: Date
    /// Bester erreichter Anteil richtiger Antworten (0…1).
    var bestScore: Double
    var timesCompleted: Int

    init(lessonID: String, completedAt: Date = .now, bestScore: Double) {
        self.lessonID = lessonID
        self.completedAt = completedAt
        self.bestScore = bestScore
        self.timesCompleted = 1
    }
}

// MARK: - Fehlerprotokoll

@Model
final class MistakeRecord {
    var lessonID: String
    /// Index des Übungs-Specs in der Lektion plus Sub-Index (für expandierte Specs).
    var exerciseIndex: Int
    var subIndex: Int
    var vocabID: String?
    var prompt: String
    var correctAnswer: String
    var timestamp: Date
    var resolvedAt: Date?

    init(
        lessonID: String,
        exerciseIndex: Int,
        subIndex: Int,
        vocabID: String?,
        prompt: String,
        correctAnswer: String,
        timestamp: Date = .now
    ) {
        self.lessonID = lessonID
        self.exerciseIndex = exerciseIndex
        self.subIndex = subIndex
        self.vocabID = vocabID
        self.prompt = prompt
        self.correctAnswer = correctAnswer
        self.timestamp = timestamp
        self.resolvedAt = nil
    }

    var isResolved: Bool { resolvedAt != nil }
}

// MARK: - Review-Historie

/// Ein Protokolleintrag pro Bewertung — Grundlage für Statistik und die
/// spätere FSRS-Migration (die volle Reviewhistorie braucht, Spec §3).
@Model
final class ReviewLogEntry {
    var vocabID: String
    var timestamp: Date
    /// SM-2-Qualität (2–5, siehe ReviewGrade).
    var grade: Int
    var intervalBefore: Int
    var intervalAfter: Int
    var easeAfter: Double

    init(
        vocabID: String,
        timestamp: Date = .now,
        grade: Int,
        intervalBefore: Int,
        intervalAfter: Int,
        easeAfter: Double
    ) {
        self.vocabID = vocabID
        self.timestamp = timestamp
        self.grade = grade
        self.intervalBefore = intervalBefore
        self.intervalAfter = intervalAfter
        self.easeAfter = easeAfter
    }
}

// MARK: - Niveau-Prüfungen

/// Ein abgeschlossener Prüfungsversuch — bestanden oder nicht.
/// Punkteschema wie DELF: vier Teile à 25, gesamt 100.
@Model
final class ExamAttempt {
    var examID: String
    var levelRaw: String
    var date: Date
    var listeningScore: Double
    var readingScore: Double
    var languageScore: Double
    var writingScore: Double
    var totalScore: Double
    var passed: Bool
    /// Sekunden vom Start bis zur Abgabe.
    var duration: Int

    init(
        examID: String,
        level: CEFRLevel,
        direction: CourseDirection = .french,
        date: Date = .now,
        listeningScore: Double,
        readingScore: Double,
        languageScore: Double,
        writingScore: Double,
        totalScore: Double,
        passed: Bool,
        duration: Int
    ) {
        self.examID = examID
        // Richtungsgetrennt: Deutsch-Versuche speichern "de:A1" (Bestand: "A1").
        self.levelRaw = direction.storageID(level.rawValue)
        self.date = date
        self.listeningScore = listeningScore
        self.readingScore = readingScore
        self.languageScore = languageScore
        self.writingScore = writingScore
        self.totalScore = totalScore
        self.passed = passed
        self.duration = duration
    }

    var level: CEFRLevel? { CEFRLevel(rawValue: CourseDirection.german.contentID(fromStorageID: levelRaw)) }

    var direction: CourseDirection { levelRaw.hasPrefix("de:") ? .german : .french }

    func score(for kind: ExamSectionKind) -> Double {
        switch kind {
        case .listening: return listeningScore
        case .reading: return readingScore
        case .language: return languageScore
        case .writing: return writingScore
        }
    }
}

/// Abschluss eines Vertiefungskapitels (optionale Komplex-Übungen pro Niveau).
@Model
final class ChallengeProgress {
    @Attribute(.unique) var chapterID: String
    var completedAt: Date
    /// Bester erreichter Anteil richtiger Antworten (0…1).
    var bestScore: Double
    var timesCompleted: Int

    init(chapterID: String, completedAt: Date = .now, bestScore: Double) {
        self.chapterID = chapterID
        self.completedAt = completedAt
        self.bestScore = bestScore
        self.timesCompleted = 1
    }
}

/// Verliehenes Zertifikat — entsteht beim ersten Bestehen der Niveau-Prüfung
/// und bleibt bestehen (spätere Versuche ändern es nicht).
@Model
final class EarnedCertificate {
    @Attribute(.unique) var levelRaw: String
    var date: Date
    /// Punktzahl des Versuchs, mit dem bestanden wurde (0–100).
    var score: Double
    /// Anzeige-Seriennummer, z. B. "FR-A1-2607-4821".
    var serial: String

    init(level: CEFRLevel, direction: CourseDirection = .french, date: Date = .now, score: Double) {
        // Richtungsgetrennt: "de:A1" für den Deutsch-Kurs — die unique-Constraint
        // erlaubt so korrekt ein Zertifikat pro Niveau UND Richtung.
        self.levelRaw = direction.storageID(level.rawValue)
        self.date = date
        self.score = score
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date) % 100
        let month = calendar.component(.month, from: date)
        self.serial = String(
            format: "%@-%@-%02d%02d-%04d",
            direction.certificateSerialPrefix, level.rawValue, year, month,
            Int.random(in: 1000...9999)
        )
    }

    var level: CEFRLevel? { CEFRLevel(rawValue: CourseDirection.german.contentID(fromStorageID: levelRaw)) }

    var direction: CourseDirection { levelRaw.hasPrefix("de:") ? .german : .french }
}

// MARK: - Einstellungen (Singleton-Datensatz)

@Model
final class UserSettings {
    var onboardingDone: Bool
    /// Tagespensum: maximal so viele neue Karten pro Tag.
    var newCardsPerDay: Int
    /// Name auf Zertifikaten (optional, in den Einstellungen änderbar).
    var certificateName: String = ""
    /// Kursrichtung — Default-Wert hält die Lightweight-Migration
    /// für Bestandsnutzer intakt (alle waren Französisch-Lerner).
    var courseDirectionRaw: String = CourseDirection.french.rawValue

    var courseDirection: CourseDirection {
        get { CourseDirection(rawValue: courseDirectionRaw) ?? .french }
        set { courseDirectionRaw = newValue.rawValue }
    }

    /// Der Content-Store des gewählten Kurses.
    var content: ContentStore { .store(for: courseDirection) }

    init() {
        self.onboardingDone = false
        self.newCardsPerDay = 10
        self.certificateName = ""
        self.courseDirectionRaw = CourseDirection.french.rawValue
    }

    static func fetchOrCreate(in context: ModelContext) -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>()
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let fresh = UserSettings()
        context.insert(fresh)
        return fresh
    }
}
