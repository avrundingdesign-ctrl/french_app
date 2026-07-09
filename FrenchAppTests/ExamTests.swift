import XCTest
import SwiftData
@testable import FrenchApp

/// Niveau-Prüfungen: Aufbau, Durchspielen, DELF-Bewertungsregeln,
/// Zertifikatvergabe und Freischaltkette.
@MainActor
final class ExamTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var content: ContentStore!

    override func setUpWithError() throws {
        let schema = Schema([
            ReviewState.self, ReviewLogEntry.self, LessonProgress.self,
            MistakeRecord.self, UserSettings.self,
            ExamAttempt.self, EarnedCertificate.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
        content = try ContentStore(bundle: Bundle(for: ContentStore.self))
    }

    // MARK: - Hilfen

    private func outcome(for question: ExamQuestion, correct: Bool) -> AnswerOutcome {
        guard correct else {
            return AnswerOutcome(correct: false, userAnswer: "xxx")
        }
        switch question.exercise.kind {
        case .multipleChoice(let mc):
            return AnswerOutcome(correct: true, userAnswer: mc.correctAnswer)
        case .textInput(let input):
            let result = input.check(input.answer)
            XCTAssertNotEqual(
                result, AnswerChecker.Result.wrong,
                "\(question.id): Musterlösung «\(input.answer)» wird nicht akzeptiert"
            )
            return AnswerOutcome(correct: true, userAnswer: input.answer)
        case .matching, .wordOrder:
            return AnswerOutcome(correct: true)
        }
    }

    /// Spielt eine Prüfung durch; `isCorrect` entscheidet pro Frage.
    @discardableResult
    private func play(
        _ exam: ExamDefinition,
        isCorrect: (ExamQuestion) -> Bool
    ) -> ExamSession {
        let session = ExamSession(exam: exam, content: content)
        session.start()
        while session.phase == .active, let question = session.current {
            session.record(outcome(for: question, correct: isCorrect(question)), context: context)
        }
        XCTAssertEqual(session.phase, .finished, exam.id)
        return session
    }

    // MARK: - Aufbau

    func testEveryExamBuildsAllQuestions() {
        XCTAssertEqual(content.exams.count, 5, "A1–C1 erwartet")
        for exam in content.exams {
            let specCount = exam.sections.flatMap(\.tasks).flatMap(\.questions).count
            let session = ExamSession(exam: exam, content: content)
            XCTAssertEqual(
                session.questions.count, specCount,
                "\(exam.id): nicht alle Fragen baubar (z. B. Konjugation ohne Verbform?)"
            )
            // Jeder der vier Teile hat Fragen — sonst wäre die 25-Punkte-Teilung sinnlos.
            for (index, section) in exam.sections.enumerated() {
                XCTAssertFalse(
                    session.questions.filter { $0.sectionIndex == index }.isEmpty,
                    "\(exam.id): Teil \(section.kind.rawValue) ohne Fragen"
                )
            }
        }
    }

    func testExamTextAnswersAreTypeable() {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789 éèêàçùâîôûëïöüœ'-")
        for exam in content.exams {
            let session = ExamSession(exam: exam, content: content)
            for question in session.questions {
                guard case .textInput(let input) = question.exercise.kind else { continue }
                let normalized = AnswerChecker.normalize(input.answer)
                XCTAssertTrue(
                    normalized.unicodeScalars.allSatisfy { allowed.contains($0) },
                    "\(question.id): Antwort «\(normalized)» enthält untippbare Zeichen"
                )
            }
        }
    }

    func testListeningTasksTrackTwoPlays() throws {
        let exam = try XCTUnwrap(content.examByLevel[.a1])
        let session = ExamSession(exam: exam, content: content)
        session.start()
        let question = try XCTUnwrap(session.questions.first { $0.audioScript != nil })
        XCTAssertEqual(session.playsRemaining[question.taskKey], 2)
        session.registerPlay(for: question)
        session.registerPlay(for: question)
        session.registerPlay(for: question)
        XCTAssertEqual(session.playsRemaining[question.taskKey], 0, "Nie unter null")
    }

    // MARK: - Bestehen & Zertifikat

    func testPerfectRunPassesAndAwardsCertificateOnce() throws {
        let exam = try XCTUnwrap(content.examByLevel[.a1])

        let first = play(exam) { _ in true }
        let result = try XCTUnwrap(first.result)
        XCTAssertEqual(result.total, 100, accuracy: 0.001)
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.certificateAwarded)
        XCTAssertTrue(result.wrongAnswers.isEmpty)

        // Wiederholung: bestanden, aber kein zweites Zertifikat.
        let second = play(exam) { _ in true }
        XCTAssertTrue(second.result?.passed ?? false)
        XCTAssertFalse(second.result?.certificateAwarded ?? true)

        let certificates = try context.fetch(FetchDescriptor<EarnedCertificate>())
        XCTAssertEqual(certificates.count, 1)
        XCTAssertEqual(certificates[0].levelRaw, "A1")
        XCTAssertEqual(certificates[0].score, 100, accuracy: 0.001)
        XCTAssertTrue(certificates[0].serial.hasPrefix("FR-A1-"))

        let attempts = try context.fetch(FetchDescriptor<ExamAttempt>())
        XCTAssertEqual(attempts.count, 2)
        XCTAssertTrue(attempts.allSatisfy(\.passed))
    }

    func testFailedRunCreatesNoCertificate() throws {
        let exam = try XCTUnwrap(content.examByLevel[.a1])
        let session = play(exam) { _ in false }
        let result = try XCTUnwrap(session.result)

        XCTAssertEqual(result.total, 0, accuracy: 0.001)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.wrongAnswers.count, session.questions.count)

        XCTAssertTrue(try context.fetch(FetchDescriptor<EarnedCertificate>()).isEmpty)
        let attempts = try context.fetch(FetchDescriptor<ExamAttempt>())
        XCTAssertEqual(attempts.count, 1)
        XCTAssertFalse(attempts[0].passed)
    }

    /// DELF-Regel: Trotz 75/100 fällt durch, wer in einem Teil unter 5 Punkten bleibt.
    func testSectionMinimumFailsDespiteHighTotal() throws {
        let exam = try XCTUnwrap(content.examByLevel[.a1])
        let session = play(exam) { $0.kind != .listening }
        let result = try XCTUnwrap(session.result)

        XCTAssertEqual(result.total, 75, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(result.total, ExamDefinition.passThreshold)
        XCTAssertFalse(result.passed, "Mindestpunktzahl je Teil muss greifen")

        let listening = try XCTUnwrap(result.sections.first { $0.kind == .listening })
        XCTAssertFalse(listening.passedMinimum)
        XCTAssertTrue(try context.fetch(FetchDescriptor<EarnedCertificate>()).isEmpty)
    }

    // MARK: - Zeitlimit

    func testExpiryCountsOpenQuestionsAsWrongAndSavesAttempt() throws {
        let exam = try XCTUnwrap(content.examByLevel[.a1])
        let session = ExamSession(exam: exam, content: content)
        session.start()

        // Zwei Fragen richtig beantworten, dann läuft die Zeit ab.
        for _ in 0..<2 {
            guard let question = session.current else { break }
            session.record(outcome(for: question, correct: true), context: context)
        }
        session.expire(context: context)

        XCTAssertEqual(session.phase, .finished)
        let result = try XCTUnwrap(session.result)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.wrongAnswers.count, session.questions.count - 2)

        let attempts = try context.fetch(FetchDescriptor<ExamAttempt>())
        XCTAssertEqual(attempts.count, 1)
    }

    func testRemainingSecondsCountsDownFromDuration() throws {
        let exam = try XCTUnwrap(content.examByLevel[.b2])
        let session = ExamSession(exam: exam, content: content)
        XCTAssertEqual(session.remainingSeconds(), exam.durationMinutes * 60)

        let start = Date()
        session.start(now: start)
        let later = start.addingTimeInterval(90)
        XCTAssertEqual(session.remainingSeconds(at: later), exam.durationMinutes * 60 - 90)
        let afterEnd = start.addingTimeInterval(TimeInterval(exam.durationMinutes * 60 + 5))
        XCTAssertEqual(session.remainingSeconds(at: afterEnd), 0)
    }

    // MARK: - Freischaltung

    func testExamUnlockRequiresAllLevelLessons() {
        var progress: [LessonProgress] = []
        var snapshot = ProgressSnapshot(progress: progress, content: content)
        XCTAssertFalse(snapshot.isExamUnlocked(.a1))

        let a1Lessons = content.lessons(for: .a1)
        for lesson in a1Lessons.dropLast() {
            progress.append(LessonProgress(lessonID: lesson.id, bestScore: 1.0))
        }
        snapshot = ProgressSnapshot(progress: progress, content: content)
        XCTAssertFalse(snapshot.isExamUnlocked(.a1), "Eine Lektion fehlt noch")

        progress.append(LessonProgress(lessonID: a1Lessons.last!.id, bestScore: 1.0))
        snapshot = ProgressSnapshot(progress: progress, content: content)
        XCTAssertTrue(snapshot.isExamUnlocked(.a1))
        XCTAssertFalse(snapshot.isExamUnlocked(.a2), "A2 braucht die A2-Lektionen")
    }

    /// C1 hat keine Lektionen — es zählt das B2-Zertifikat.
    func testC1UnlocksViaB2Certificate() {
        let snapshot = ProgressSnapshot(progress: [], content: content)
        XCTAssertFalse(snapshot.isExamUnlocked(.c1))
        XCTAssertFalse(snapshot.isExamUnlocked(.c1, earnedLevels: [.a1, .b1]))
        XCTAssertTrue(snapshot.isExamUnlocked(.c1, earnedLevels: [.b2]))
    }
}
