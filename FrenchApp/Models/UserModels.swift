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

// MARK: - Einstellungen (Singleton-Datensatz)

@Model
final class UserSettings {
    var onboardingDone: Bool
    /// Tagespensum: maximal so viele neue Karten pro Tag.
    var newCardsPerDay: Int

    init() {
        self.onboardingDone = false
        self.newCardsPerDay = 10
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
