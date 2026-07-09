import Foundation
import Observation
import SwiftData

enum SessionMode {
    case lesson(CourseLesson)
    case mistakes([MistakeRecord])
}

struct AnswerOutcome {
    let correct: Bool
    /// Richtig bis auf Akzente — zählt als richtig, Feedback weist darauf hin.
    let accentHint: Bool
    let userAnswer: String?

    init(correct: Bool, accentHint: Bool = false, userAnswer: String? = nil) {
        self.correct = correct
        self.accentHint = accentHint
        self.userAnswer = userAnswer
    }
}

/// Ablaufsteuerung einer Lernsequenz (Spec Screen 3):
/// Übungen nacheinander, sofortiges Feedback, am Ende Fortschritt + SRS-Einspeisung.
@Observable
final class LessonSession {
    struct Feedback {
        let correct: Bool
        let accentHint: Bool
        let correctAnswer: String
        let explanation: String?
    }

    struct Summary {
        var correctCount = 0
        var total = 0
        var newWordsEnrolled: [VocabItem] = []
        var mistakes = 0
        var nextLessonTitle: String?

        var score: Double { total > 0 ? Double(correctCount) / Double(total) : 0 }
    }

    enum Phase { case active, finished }

    let mode: SessionMode
    private let content: ContentStore
    private let factory: ExerciseFactory

    private(set) var exercises: [RuntimeExercise] = []
    private(set) var index = 0
    private(set) var phase: Phase = .active
    private(set) var feedback: Feedback?
    private(set) var summary = Summary()

    private var outcomes: [String: AnswerOutcome] = [:]
    /// Für den Fehler-Übungsmodus: Referenz → zugehörige Protokolleinträge.
    private var recordsByRef: [ExerciseRef: [MistakeRecord]] = [:]

    init(mode: SessionMode, content: ContentStore = .shared) {
        self.mode = mode
        self.content = content
        self.factory = ExerciseFactory(content: content)

        switch mode {
        case .lesson(let lesson):
            self.exercises = factory.exercises(for: lesson)
        case .mistakes(let records):
            var built: [RuntimeExercise] = []
            var seen = Set<ExerciseRef>()
            for record in records where record.resolvedAt == nil {
                let ref = ExerciseRef(
                    lessonID: record.lessonID,
                    exerciseIndex: record.exerciseIndex,
                    subIndex: record.subIndex
                )
                recordsByRef[ref, default: []].append(record)
                guard !seen.contains(ref) else { continue }
                seen.insert(ref)
                if let exercise = factory.exercise(for: ref) {
                    built.append(exercise)
                }
            }
            self.exercises = built.shuffled()
        }
    }

    var current: RuntimeExercise? {
        exercises.indices.contains(index) ? exercises[index] : nil
    }

    var progress: Double {
        exercises.isEmpty ? 0 : Double(index) / Double(exercises.count)
    }

    var isLessonMode: Bool {
        if case .lesson = mode { return true }
        return false
    }

    // MARK: - Ablauf

    func record(_ outcome: AnswerOutcome) {
        guard let exercise = current, feedback == nil else { return }
        outcomes[exercise.id] = outcome

        let explanation: String?
        switch exercise.kind {
        case .multipleChoice(let mc): explanation = mc.explanation
        case .textInput(let input): explanation = input.translation ?? input.hint
        case .wordOrder(let order): explanation = order.de
        case .matching: explanation = nil
        }

        feedback = Feedback(
            correct: outcome.correct,
            accentHint: outcome.accentHint,
            correctAnswer: correctAnswerText(for: exercise),
            explanation: explanation
        )
    }

    func advance(context: ModelContext) {
        feedback = nil
        if index + 1 < exercises.count {
            index += 1
        } else {
            finalize(context: context)
            phase = .finished
        }
    }

    private func correctAnswerText(for exercise: RuntimeExercise) -> String {
        switch exercise.kind {
        case .multipleChoice(let mc): return mc.correctAnswer
        case .textInput(let input): return input.fullSolution
        case .wordOrder(let order): return order.tokens.joined(separator: " ")
        case .matching: return exercise.answerSummary
        }
    }

    // MARK: - Abschluss

    private func finalize(context: ModelContext, now: Date = .now) {
        summary.total = exercises.count
        summary.correctCount = exercises.filter { outcomes[$0.id]?.correct == true }.count
        let wrong = exercises.filter { outcomes[$0.id]?.correct != true }
        summary.mistakes = wrong.count

        switch mode {
        case .lesson(let lesson):
            finalizeLesson(lesson, wrong: wrong, context: context, now: now)
        case .mistakes:
            finalizeMistakePractice(context: context, now: now)
        }
    }

    private func finalizeLesson(
        _ lesson: CourseLesson,
        wrong: [RuntimeExercise],
        context: ModelContext,
        now: Date
    ) {
        // Fortschritt speichern (bester Score bleibt erhalten).
        let descriptor = FetchDescriptor<LessonProgress>()
        let existing = ((try? context.fetch(descriptor)) ?? []).first { $0.lessonID == lesson.id }
        if let existing {
            existing.completedAt = now
            existing.bestScore = max(existing.bestScore, summary.score)
            existing.timesCompleted += 1
        } else {
            context.insert(LessonProgress(lessonID: lesson.id, completedAt: now, bestScore: summary.score))
        }

        // Neue Vokabeln in den SRS-Pool (Spec §3) — unter der richtungs-
        // präfixierten ID, damit beide Kurse getrennte Lernstände haben.
        SRSService.enroll(vocabIDs: lesson.newVocab.map { content.srsID(for: $0) }, context: context, now: now)
        summary.newWordsEnrolled = lesson.newVocab.compactMap { content.vocab($0) }

        // Fehler protokollieren + SRS-Zustand der betroffenen Vokabel zurücksetzen.
        for exercise in wrong {
            context.insert(MistakeRecord(
                lessonID: exercise.ref.lessonID,
                exerciseIndex: exercise.ref.exerciseIndex,
                subIndex: exercise.ref.subIndex,
                vocabID: exercise.vocabID,
                prompt: exercise.promptSummary,
                correctAnswer: exercise.answerSummary,
                timestamp: now
            ))
            if let vocabID = exercise.vocabID {
                SRSService.resetForMistake(vocabID: content.srsID(for: vocabID), context: context, now: now)
            }
        }

        if let next = content.lesson(after: lesson) {
            summary.nextLessonTitle = next.title
        }
    }

    private func finalizeMistakePractice(context: ModelContext, now: Date) {
        for exercise in exercises {
            guard outcomes[exercise.id]?.correct == true else { continue }
            for record in recordsByRef[exercise.ref] ?? [] {
                record.resolvedAt = now
            }
        }
    }
}
