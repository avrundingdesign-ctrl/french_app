import Foundation
import SwiftData

/// Vokabeltrainer-Logik über den SM-2-Zuständen (Spec §3).
enum SRSService {
    // MARK: - Fälligkeit

    struct Queue {
        var due: [ReviewState]
        var fresh: [ReviewState]
        var all: [ReviewState] { due + fresh }
        var isEmpty: Bool { due.isEmpty && fresh.isEmpty }
    }

    /// Fällige Karten (Reviews) plus neue Karten bis zum Tagespensum.
    static func buildQueue(states: [ReviewState], settings: UserSettings, now: Date = .now) -> Queue {
        let due = states
            .filter { $0.isDue(at: now) }
            .sorted { $0.nextReview < $1.nextReview }

        let introducedToday = states.filter {
            guard let first = $0.firstReviewedAt else { return false }
            return Calendar.current.isDate(first, inSameDayAs: now)
        }.count

        let freshBudget = max(0, settings.newCardsPerDay - introducedToday)
        let fresh = states
            .filter(\.isNew)
            .sorted { $0.introducedAt < $1.introducedAt }
            .prefix(freshBudget)

        return Queue(due: due, fresh: Array(fresh))
    }

    static func dueCount(states: [ReviewState], settings: UserSettings, now: Date = .now) -> Int {
        let queue = buildQueue(states: states, settings: settings, now: now)
        return queue.due.count + queue.fresh.count
    }

    // MARK: - Bewertung anwenden

    static func apply(
        grade: ReviewGrade,
        to state: ReviewState,
        context: ModelContext? = nil,
        now: Date = .now
    ) {
        let before = SM2.State(
            easeFactor: state.easeFactor,
            repetitions: state.repetitions,
            interval: state.interval
        )
        let after = SM2.review(before, quality: grade.rawValue)

        if !grade.isCorrect && state.firstReviewedAt != nil && state.repetitions > 0 {
            state.lapses += 1
        }

        state.easeFactor = after.easeFactor
        state.repetitions = after.repetitions
        state.interval = after.interval
        state.nextReview = nextReviewDate(intervalDays: after.interval, from: now)
        if state.firstReviewedAt == nil { state.firstReviewedAt = now }
        state.lastReviewedAt = now
        state.totalReviews += 1

        // Historie fürs Profil und die spätere FSRS-Migration.
        context?.insert(ReviewLogEntry(
            vocabID: state.vocabID,
            timestamp: now,
            grade: grade.rawValue,
            intervalBefore: before.interval,
            intervalAfter: after.interval,
            easeAfter: after.easeFactor
        ))
    }

    /// Vorschau des Intervalls für die Button-Beschriftung ("Gut · 6 T").
    static func previewInterval(for grade: ReviewGrade, state: ReviewState) -> Int {
        let before = SM2.State(
            easeFactor: state.easeFactor,
            repetitions: state.repetitions,
            interval: state.interval
        )
        return SM2.review(before, quality: grade.rawValue).interval
    }

    static func nextReviewDate(intervalDays: Int, from now: Date) -> Date {
        let startOfDay = Calendar.current.startOfDay(for: now)
        return Calendar.current.date(byAdding: .day, value: intervalDays, to: startOfDay) ?? startOfDay
    }

    // MARK: - Einspeisen & Fehler-Reset

    /// Nimmt neue Vokabeln in den SRS-Pool auf (nach Lektionsabschluss).
    /// Liefert die Anzahl tatsächlich neu angelegter Karten.
    @discardableResult
    static func enroll(vocabIDs: [String], context: ModelContext, now: Date = .now) -> Int {
        let existing = fetchStates(context: context)
        let known = Set(existing.map(\.vocabID))
        var created = 0
        for id in vocabIDs where !known.contains(id) {
            context.insert(ReviewState(vocabID: id, now: now))
            created += 1
        }
        return created
    }

    /// Fehler in Lektionsübungen setzen den SRS-Zustand zurück (Spec §3):
    /// Karte wird sofort wieder fällig, Wiederholungszähler auf 0.
    /// Der Ease-Faktor bleibt unverändert — ein Lektionsfehler ist keine Review-Bewertung.
    static func resetForMistake(vocabID: String, context: ModelContext, now: Date = .now) {
        guard let state = fetchStates(context: context).first(where: { $0.vocabID == vocabID }) else {
            return
        }
        if state.repetitions > 0 { state.lapses += 1 }
        state.repetitions = 0
        state.interval = 0
        state.nextReview = Calendar.current.startOfDay(for: now)
    }

    static func fetchStates(context: ModelContext) -> [ReviewState] {
        (try? context.fetch(FetchDescriptor<ReviewState>())) ?? []
    }
}
