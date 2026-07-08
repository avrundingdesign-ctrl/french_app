import XCTest
import SwiftData
@testable import FrenchApp

/// Spielt die Nutzer-Workflows auf Logik-Ebene komplett durch:
/// jede Lektion des Kurses, Fehler- und Wiederholungspfade, Freischaltkette,
/// SRS-Training über mehrere Tage. Die UI ruft exakt diese Pfade auf.
@MainActor
final class WorkflowTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var content: ContentStore!

    override func setUpWithError() throws {
        let schema = Schema([
            ReviewState.self, ReviewLogEntry.self, LessonProgress.self,
            MistakeRecord.self, UserSettings.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
        content = try ContentStore(bundle: Bundle(for: ContentStore.self))
    }

    // MARK: - Hilfen

    /// Baut die Antwort, die ein Nutzer geben würde.
    /// Bei Freitext läuft die kanonische Lösung durch den echten AnswerChecker —
    /// das stellt sicher, dass jede Musterlösung auch als richtig erkannt wird.
    private func outcome(for exercise: RuntimeExercise, correct: Bool) -> AnswerOutcome {
        guard correct else {
            return AnswerOutcome(correct: false, userAnswer: "xxx")
        }
        switch exercise.kind {
        case .multipleChoice(let mc):
            return AnswerOutcome(correct: true, userAnswer: mc.correctAnswer)
        case .textInput(let input):
            let result = input.check(input.answer)
            XCTAssertNotEqual(
                result, AnswerChecker.Result.wrong,
                "\(exercise.id): Musterlösung «\(input.answer)» wird nicht akzeptiert"
            )
            return AnswerOutcome(correct: true, userAnswer: input.answer)
        case .matching, .wordOrder:
            return AnswerOutcome(correct: true)
        }
    }

    @discardableResult
    private func play(_ lesson: CourseLesson, correct: Bool) -> LessonSession {
        let session = LessonSession(mode: .lesson(lesson), content: content)
        XCTAssertFalse(session.exercises.isEmpty, "\(lesson.id): keine Übungen")
        while session.phase == .active, let exercise = session.current {
            session.record(outcome(for: exercise, correct: correct))
            XCTAssertNotNil(session.feedback, "\(exercise.id): kein Feedback")
            session.advance(context: context)
        }
        XCTAssertEqual(session.phase, .finished, lesson.id)
        return session
    }

    // MARK: - Workflow: jede Lektion des Kurses komplett durchspielen

    func testEveryLessonPlaysThroughEndToEnd() throws {
        for lesson in content.orderedLessons {
            let session = play(lesson, correct: true)
            XCTAssertEqual(session.summary.mistakes, 0, lesson.id)
            XCTAssertEqual(session.summary.score, 1.0, accuracy: 0.001, lesson.id)
            XCTAssertEqual(
                session.summary.newWordsEnrolled.count, lesson.newVocab.count,
                "\(lesson.id): nicht alle neuen Wörter eingespeist"
            )
        }

        // Danach: kompletter Kurs abgeschlossen, alle Vokabeln im SRS-Pool.
        let progress = try context.fetch(FetchDescriptor<LessonProgress>())
        XCTAssertEqual(progress.count, content.orderedLessons.count)

        let states = SRSService.fetchStates(context: context)
        let expected = Set(content.orderedLessons.flatMap(\.newVocab))
        XCTAssertEqual(Set(states.map(\.vocabID)), expected)

        let snapshot = ProgressSnapshot(progress: progress, content: content)
        XCTAssertNil(snapshot.nextLesson, "Nach dem Finale darf nichts mehr offen sein")
        XCTAssertEqual(
            snapshot.coveredGrammarCount, content.grammarRules.count,
            "Jede Grammatikregel muss über Lektionen erreichbar sein"
        )
        for level in content.levels {
            let (done, total) = snapshot.levelProgress(level)
            XCTAssertEqual(done, total, "\(level.rawValue) unvollständig")
        }

        // Keine Fehler geloggt, keine Karte fälschlich zurückgesetzt.
        let mistakes = try context.fetch(FetchDescriptor<MistakeRecord>())
        XCTAssertTrue(mistakes.isEmpty)
    }

    // MARK: - Workflow: Freischaltkette

    func testUnlockChainAcrossAllLevels() throws {
        var completed: [LessonProgress] = []
        for (index, lesson) in content.orderedLessons.enumerated() {
            let snapshot = ProgressSnapshot(progress: completed, content: content)
            XCTAssertTrue(snapshot.isUnlocked(lesson), "\(lesson.id) müsste offen sein")
            XCTAssertEqual(snapshot.nextLesson?.id, lesson.id)

            // Alles danach ist noch gesperrt.
            if index + 1 < content.orderedLessons.count {
                let next = content.orderedLessons[index + 1]
                XCTAssertFalse(snapshot.isUnlocked(next), "\(next.id) dürfte noch zu sein")
            }
            completed.append(LessonProgress(lessonID: lesson.id, bestScore: 1.0))
        }
    }

    // MARK: - Workflow: Fehler machen → Fehler üben → gelöst

    func testMistakeWorkflowLogsResetsAndResolves() throws {
        let lesson = content.orderedLessons[0]

        // 1. Lektion fehlerfrei abschließen und eine Vokabel im Training festigen.
        play(lesson, correct: true)
        let states = SRSService.fetchStates(context: context)
        let trained = try XCTUnwrap(states.first { $0.vocabID == lesson.newVocab[0] })
        SRSService.apply(grade: .good, to: trained, context: context)
        SRSService.apply(grade: .good, to: trained, context: context)
        XCTAssertEqual(trained.interval, 6)

        // 2. Lektion wiederholen — alles falsch.
        let failed = play(lesson, correct: false)
        XCTAssertEqual(failed.summary.mistakes, failed.exercises.count)
        XCTAssertEqual(failed.summary.score, 0, accuracy: 0.001)

        let records = try context.fetch(FetchDescriptor<MistakeRecord>())
        XCTAssertEqual(records.count, failed.exercises.count)
        XCTAssertTrue(records.allSatisfy { !$0.isResolved })

        // Bester Score bleibt, Zähler steigt, SRS-Zustand wurde zurückgesetzt.
        let progress = try context.fetch(FetchDescriptor<LessonProgress>())
        XCTAssertEqual(progress.count, 1)
        XCTAssertEqual(progress[0].bestScore, 1.0)
        XCTAssertEqual(progress[0].timesCompleted, 2)
        XCTAssertEqual(trained.repetitions, 0)
        XCTAssertTrue(trained.isDue(at: .now))
        // Doppelt eingespeist wird nicht:
        XCTAssertEqual(SRSService.fetchStates(context: context).count, lesson.newVocab.count)

        // 3. „Fehler üben" — alles richtig → alle Einträge gelöst.
        let practice = LessonSession(mode: .mistakes(records), content: content)
        XCTAssertEqual(practice.exercises.count, failed.exercises.count)
        XCTAssertFalse(practice.isLessonMode)
        while practice.phase == .active, let exercise = practice.current {
            practice.record(outcome(for: exercise, correct: true))
            practice.advance(context: context)
        }
        XCTAssertTrue(records.allSatisfy(\.isResolved))

        // Kein neuer Lektionsfortschritt durch den Übungsmodus:
        XCTAssertEqual(try context.fetch(FetchDescriptor<LessonProgress>()).count, 1)
    }

    func testMistakePracticeWithWrongAnswersKeepsRecordsOpen() throws {
        let lesson = content.orderedLessons[0]
        play(lesson, correct: false)
        let records = try context.fetch(FetchDescriptor<MistakeRecord>())

        let practice = LessonSession(mode: .mistakes(records), content: content)
        while practice.phase == .active, let exercise = practice.current {
            practice.record(outcome(for: exercise, correct: false))
            practice.advance(context: context)
        }
        XCTAssertTrue(records.allSatisfy { !$0.isResolved }, "Falsch geübt bleibt offen")
    }

    func testStaleMistakeRecordsProduceEmptyPracticeSession() {
        let stale = MistakeRecord(
            lessonID: "geloeschte_lektion", exerciseIndex: 9, subIndex: 9,
            vocabID: nil, prompt: "?", correctAnswer: "?"
        )
        context.insert(stale)
        let practice = LessonSession(mode: .mistakes([stale]), content: content)
        XCTAssertTrue(practice.exercises.isEmpty, "Stale Refs → leere Session (UI zeigt Hinweis)")
    }

    // MARK: - Workflow: Vokabeltraining über mehrere Tage

    func testReviewWorkflowAcrossDays() throws {
        let settings = UserSettings()
        settings.newCardsPerDay = 3
        context.insert(settings)

        let calendar = Calendar.current
        let day0 = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let day1 = calendar.date(byAdding: .day, value: 1, to: day0)!
        let day2 = calendar.date(byAdding: .day, value: 2, to: day0)!

        SRSService.enroll(vocabIDs: ["v_a", "v_b", "v_c", "v_d", "v_e"], context: context, now: day0)
        let states = SRSService.fetchStates(context: context)

        // Tag 0: nur das Tagespensum an neuen Karten.
        var queue = SRSService.buildQueue(states: states, settings: settings, now: day0)
        XCTAssertEqual(queue.due.count, 0)
        XCTAssertEqual(queue.fresh.count, 3)

        for state in queue.fresh {
            SRSService.apply(grade: .good, to: state, context: context, now: day0)
        }
        // Pensum aufgebraucht — keine weiteren neuen Karten heute.
        queue = SRSService.buildQueue(states: states, settings: settings, now: day0)
        XCTAssertTrue(queue.isEmpty)

        // Tag 1: die drei Karten sind fällig, Pensum ist wieder frei (2 neue übrig).
        queue = SRSService.buildQueue(states: states, settings: settings, now: day1)
        XCTAssertEqual(queue.due.count, 3)
        XCTAssertEqual(queue.fresh.count, 2)

        let again = queue.due[0]
        let good = queue.due[1]
        let easy = queue.due[2]
        SRSService.apply(grade: .again, to: again, context: context, now: day1)
        SRSService.apply(grade: .good, to: good, context: context, now: day1)
        SRSService.apply(grade: .easy, to: easy, context: context, now: day1)

        XCTAssertEqual(again.interval, 1)   // morgen wieder
        XCTAssertEqual(good.interval, 6)    // zweite erfolgreiche Wiederholung
        XCTAssertEqual(easy.interval, 6)
        XCTAssertGreaterThan(easy.easeFactor, good.easeFactor)

        // Tag 2: nur die Nochmal-Karte ist fällig.
        queue = SRSService.buildQueue(states: states, settings: settings, now: day2)
        XCTAssertEqual(queue.due.map(\.vocabID), [again.vocabID])

        // Historie: 6 Bewertungen geloggt.
        let log = try context.fetch(FetchDescriptor<ReviewLogEntry>())
        XCTAssertEqual(log.count, 6)
    }

    func testChangingDailyGoalAffectsQueueImmediately() {
        let settings = UserSettings()
        settings.newCardsPerDay = 5
        context.insert(settings)
        SRSService.enroll(vocabIDs: (1...20).map { "v_\($0)" }, context: context)
        let states = SRSService.fetchStates(context: context)

        XCTAssertEqual(SRSService.buildQueue(states: states, settings: settings).fresh.count, 5)
        settings.newCardsPerDay = 12
        XCTAssertEqual(SRSService.buildQueue(states: states, settings: settings).fresh.count, 12)
    }

    // MARK: - Workflow: Zurücksetzen (Einstellungen)

    func testResetWorkflowsLeaveConsistentState() throws {
        // Fortschritt aufbauen.
        play(content.orderedLessons[0], correct: true)
        let states = SRSService.fetchStates(context: context)
        SRSService.apply(grade: .good, to: states[0], context: context)

        // „Vokabeltraining zurücksetzen": States + Log weg, Lektionen bleiben.
        for state in states { context.delete(state) }
        for entry in try context.fetch(FetchDescriptor<ReviewLogEntry>()) { context.delete(entry) }
        XCTAssertTrue(SRSService.fetchStates(context: context).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LessonProgress>()).count, 1)

        // Lektion erneut abschließen speist die Wörter wieder ein.
        play(content.orderedLessons[0], correct: true)
        XCTAssertEqual(
            SRSService.fetchStates(context: context).count,
            content.orderedLessons[0].newVocab.count
        )
    }

    // MARK: - Inhaltliche Korrektheit der gebauten Übungen

    /// Matching ist nur lösbar, wenn innerhalb einer Übung keine zwei Karten
    /// denselben Text tragen — sonst kann der Nutzer die Paare nicht unterscheiden.
    func testMatchingPairsAreUnambiguous() {
        let factory = ExerciseFactory(content: content)
        for lesson in content.orderedLessons {
            for exercise in factory.exercises(for: lesson) {
                guard case .matching(let matching) = exercise.kind else { continue }
                let frs = matching.pairs.map(\.fr)
                let des = matching.pairs.map(\.de)
                XCTAssertEqual(frs.count, Set(frs).count, "\(exercise.id): doppelte FR-Seite")
                XCTAssertEqual(des.count, Set(des).count, "\(exercise.id): doppelte DE-Seite")
            }
        }
    }

    /// Freitext-Antworten müssen mit iOS-Tastatur + Akzentleiste tippbar sein.
    /// Maßgeblich ist die normalisierte Form — Satzzeichen ignoriert der
    /// AnswerChecker beim Vergleich ohnehin.
    func testTextInputAnswersAreTypeable() {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789 éèêàçùâîôûëïöüœ'-")
        let factory = ExerciseFactory(content: content)
        for lesson in content.orderedLessons {
            for exercise in factory.exercises(for: lesson) {
                guard case .textInput(let input) = exercise.kind else { continue }
                let normalized = AnswerChecker.normalize(input.answer)
                XCTAssertTrue(
                    normalized.unicodeScalars.allSatisfy { allowed.contains($0) },
                    "\(exercise.id): Antwort «\(normalized)» enthält untippbare Zeichen"
                )
            }
        }
    }

    /// Jede Grammatikregel muss von mindestens einer Lektion behandelt werden,
    /// sonst ist sie im Profil nie „abgedeckt".
    func testEveryGrammarRuleIsCoveredBySomeLesson() {
        for rule in content.grammarRules {
            XCTAssertFalse(
                content.lessons(covering: rule.id).isEmpty,
                "Regel \(rule.id) hängt an keiner Lektion"
            )
        }
    }
}
