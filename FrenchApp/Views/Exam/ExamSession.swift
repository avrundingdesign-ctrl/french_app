import Foundation
import Observation
import SwiftData

// MARK: - Laufzeit-Frage

/// Eine Prüfungsfrage samt Kontext ihres Aufgabenblocks (Lesetext, Audio, Situation).
struct ExamQuestion: Identifiable {
    let exercise: RuntimeExercise
    let sectionIndex: Int
    let taskIndex: Int
    let kind: ExamSectionKind
    let context: String?
    let audioScript: String?
    let passage: String?
    let passageTitle: String?
    /// Erste Frage ihres Abschnitts — die UI zeigt davor die Teil-Überschrift.
    let isFirstOfSection: Bool

    var id: String { exercise.id }
    /// Schlüssel des Aufgabenblocks (für das Abspiel-Limit beim Hören).
    var taskKey: String { "\(sectionIndex)#\(taskIndex)" }
}

// MARK: - Session

/// Ablaufsteuerung einer Niveau-Prüfung: kein Feedback während der Prüfung,
/// festes Zeitlimit mit automatischer Abgabe, Bewertung nach DELF-Schema
/// (vier Teile à 25 Punkte, bestanden ab 50 gesamt und 5 je Teil).
@Observable
final class ExamSession {
    enum Phase { case intro, active, finished }

    struct SectionResult: Identifiable {
        let kind: ExamSectionKind
        let correct: Int
        let total: Int

        var points: Double {
            total > 0 ? Double(correct) / Double(total) * ExamDefinition.sectionPoints : 0
        }
        var passedMinimum: Bool { points >= ExamDefinition.sectionMinimum }
        var id: String { kind.rawValue }
    }

    struct WrongAnswer: Identifiable {
        let id: String
        let kind: ExamSectionKind
        let prompt: String
        let correctAnswer: String
        let userAnswer: String?
    }

    struct Result {
        let sections: [SectionResult]
        let wrongAnswers: [WrongAnswer]
        /// True, wenn dieser Versuch das Zertifikat neu verliehen hat.
        var certificateAwarded = false

        var total: Double { sections.reduce(0) { $0 + $1.points } }
        var passed: Bool {
            total >= ExamDefinition.passThreshold && sections.allSatisfy(\.passedMinimum)
        }
    }

    let exam: ExamDefinition
    private(set) var questions: [ExamQuestion] = []
    private(set) var index = 0
    private(set) var phase: Phase = .intro
    private(set) var result: Result?
    private(set) var startedAt: Date?
    private(set) var deadline: Date?
    /// Kursrichtung der Prüfung — bestimmt TTS-Stimme und Zertifikat-Namensraum.
    let direction: CourseDirection

    private var outcomes: [String: AnswerOutcome] = [:]
    /// Verbleibende Abspielvorgänge je Hör-Aufgabe (wie DELF: zweimal hören).
    private(set) var playsRemaining: [String: Int] = [:]

    static let playsPerAudio = 2

    init(exam: ExamDefinition, content: ContentStore = .shared) {
        self.exam = exam
        self.direction = content.direction
        let factory = ExerciseFactory(content: content)

        var built: [ExamQuestion] = []
        for (sectionIndex, section) in exam.sections.enumerated() {
            var firstOfSection = true
            for (taskIndex, task) in section.tasks.enumerated() {
                for (questionIndex, spec) in task.questions.enumerated() {
                    // Frage-Position stabil in der Ref kodiert (Prüfung statt Lektion).
                    let ref = ExerciseRef(
                        lessonID: exam.id,
                        exerciseIndex: sectionIndex * 100 + taskIndex,
                        subIndex: questionIndex
                    )
                    guard let exercise = factory.standaloneExercise(spec: spec, ref: ref) else {
                        continue
                    }
                    built.append(ExamQuestion(
                        exercise: exercise,
                        sectionIndex: sectionIndex,
                        taskIndex: taskIndex,
                        kind: section.kind,
                        context: task.context,
                        audioScript: task.audioScript,
                        passage: task.passage,
                        passageTitle: task.passageTitle,
                        isFirstOfSection: firstOfSection
                    ))
                    firstOfSection = false
                }
                if section.kind == .listening, task.audioScript != nil {
                    playsRemaining["\(sectionIndex)#\(taskIndex)"] = Self.playsPerAudio
                }
            }
        }
        self.questions = built
    }

    var current: ExamQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    var progress: Double {
        questions.isEmpty ? 0 : Double(index) / Double(questions.count)
    }

    // MARK: - Ablauf

    func start(now: Date = .now) {
        guard phase == .intro else { return }
        startedAt = now
        deadline = now.addingTimeInterval(TimeInterval(exam.durationMinutes * 60))
        phase = .active
    }

    func remainingSeconds(at date: Date = .now) -> Int {
        guard let deadline else { return exam.durationMinutes * 60 }
        return max(0, Int(deadline.timeIntervalSince(date).rounded()))
    }

    /// Antwort speichern und sofort weiter — Auswertung erst am Ende.
    func record(_ outcome: AnswerOutcome, context: ModelContext, now: Date = .now) {
        guard phase == .active, let question = current else { return }
        outcomes[question.id] = outcome
        if index + 1 < questions.count {
            index += 1
        } else {
            finalize(context: context, now: now)
        }
    }

    /// Zeit abgelaufen: automatische Abgabe, offene Fragen zählen als falsch.
    func expire(context: ModelContext, now: Date = .now) {
        guard phase == .active else { return }
        finalize(context: context, now: now)
    }

    func registerPlay(for question: ExamQuestion) {
        guard let remaining = playsRemaining[question.taskKey], remaining > 0 else { return }
        playsRemaining[question.taskKey] = remaining - 1
    }

    // MARK: - Auswertung

    private func finalize(context: ModelContext, now: Date) {
        var sections: [SectionResult] = []
        for (sectionIndex, section) in exam.sections.enumerated() {
            let sectionQuestions = questions.filter { $0.sectionIndex == sectionIndex }
            let correct = sectionQuestions.filter { outcomes[$0.id]?.correct == true }.count
            sections.append(SectionResult(
                kind: section.kind,
                correct: correct,
                total: sectionQuestions.count
            ))
        }

        let wrong = questions
            .filter { outcomes[$0.id]?.correct != true }
            .map { question in
                WrongAnswer(
                    id: question.id,
                    kind: question.kind,
                    prompt: question.exercise.promptSummary,
                    correctAnswer: question.exercise.answerSummary,
                    userAnswer: outcomes[question.id]?.userAnswer
                )
            }

        var result = Result(sections: sections, wrongAnswers: wrong)

        let attempt = ExamAttempt(
            examID: exam.id,
            level: exam.level,
            direction: direction,
            date: now,
            listeningScore: sections.first { $0.kind == .listening }?.points ?? 0,
            readingScore: sections.first { $0.kind == .reading }?.points ?? 0,
            languageScore: sections.first { $0.kind == .language }?.points ?? 0,
            writingScore: sections.first { $0.kind == .writing }?.points ?? 0,
            totalScore: result.total,
            passed: result.passed,
            duration: startedAt.map { Int(now.timeIntervalSince($0)) } ?? 0
        )
        context.insert(attempt)

        if result.passed {
            // Zertifikate sind pro Richtung getrennt ("A1" bzw. "de:A1").
            let levelRaw = direction.storageID(exam.level.rawValue)
            let descriptor = FetchDescriptor<EarnedCertificate>(
                predicate: #Predicate { $0.levelRaw == levelRaw }
            )
            if ((try? context.fetch(descriptor)) ?? []).isEmpty {
                context.insert(EarnedCertificate(level: exam.level, direction: direction, date: now, score: result.total))
                result.certificateAwarded = true
            }
        }

        self.result = result
        phase = .finished
    }
}
