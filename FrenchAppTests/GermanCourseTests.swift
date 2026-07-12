import XCTest
import SwiftData
@testable import FrenchApp

/// Deutsch-Kurs (Phase 5a): spielt jede Lektion der Gegenrichtung durch,
/// prüft die SRS-Trennung per Präfix-IDs und dass Prüfung/Hörtraining
/// vollständig aus den _de-Dateien aufgebaut werden.
@MainActor
final class GermanCourseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var german: ContentStore!
    private var french: ContentStore!

    override func setUpWithError() throws {
        let schema = Schema([
            ReviewState.self, ReviewLogEntry.self, LessonProgress.self,
            MistakeRecord.self, UserSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
        german = try ContentStore(bundle: Bundle(for: ContentStore.self), direction: .german)
        french = try ContentStore(bundle: Bundle(for: ContentStore.self), direction: .french)
    }

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
    private func play(_ lesson: CourseLesson) -> LessonSession {
        let session = LessonSession(mode: .lesson(lesson), content: german)
        XCTAssertFalse(session.exercises.isEmpty, "\(lesson.id): keine Übungen")
        while session.phase == .active, let exercise = session.current {
            session.record(outcome(for: exercise, correct: true))
            session.advance(context: context)
        }
        XCTAssertEqual(session.phase, .finished, lesson.id)
        return session
    }

    // MARK: - Kursstruktur

    func testGermanCourseHas72LessonsAcrossA1A2AndB1() {
        XCTAssertEqual(german.orderedLessons.count, 72)
        XCTAssertEqual(german.levels, [.a1, .a2, .b1])
        XCTAssertTrue(german.orderedLessons.allSatisfy { $0.id.hasPrefix("de_") })
        // A1 kommt im Pfad vor A2, A2 vor B1.
        XCTAssertTrue(german.orderedLessons.prefix(24).allSatisfy { $0.id.hasPrefix("de_a1_") })
        XCTAssertTrue(german.orderedLessons[24..<48].allSatisfy { $0.id.hasPrefix("de_a2_") })
        XCTAssertTrue(german.orderedLessons.suffix(24).allSatisfy { $0.id.hasPrefix("de_b1_") })
        // Kein Überschneiden mit den Lektions-IDs des Französisch-Kurses.
        let frenchIDs = Set(french.orderedLessons.map(\.id))
        XCTAssertTrue(frenchIDs.isDisjoint(with: german.orderedLessons.map(\.id)))
    }

    func testEveryGermanLessonPlaysThroughEndToEnd() throws {
        for lesson in german.orderedLessons {
            let session = play(lesson)
            XCTAssertEqual(session.summary.mistakes, 0, lesson.id)
            XCTAssertEqual(
                session.summary.newWordsEnrolled.count, lesson.newVocab.count,
                "\(lesson.id): nicht alle neuen Wörter eingespeist"
            )
        }
        let progress = try context.fetch(FetchDescriptor<LessonProgress>())
        XCTAssertEqual(progress.count, german.orderedLessons.count)

        let snapshot = ProgressSnapshot(progress: progress, content: german)
        XCTAssertNil(snapshot.nextLesson)
        XCTAssertEqual(
            snapshot.coveredGrammarCount, german.grammarRules.count,
            "Jede deutsche Grammatikregel muss über Lektionen erreichbar sein"
        )
    }

    // MARK: - SRS-Trennung (Präfix-IDs)

    func testGermanLessonEnrollsPrefixedStatesInvisibleToFrenchCourse() throws {
        let lesson = german.orderedLessons[0]
        play(lesson)

        let states = SRSService.fetchStates(context: context)
        XCTAssertEqual(states.count, lesson.newVocab.count)
        XCTAssertTrue(states.allSatisfy { $0.vocabID.hasPrefix("de:") })

        // Der Deutsch-Store löst sie auf, der Französisch-Store filtert sie aus.
        for state in states {
            XCTAssertNotNil(german.vocab(forReviewID: state.vocabID))
            XCTAssertNil(french.vocab(forReviewID: state.vocabID))
            XCTAssertTrue(CourseDirection.german.owns(storageID: state.vocabID))
            XCTAssertFalse(CourseDirection.french.owns(storageID: state.vocabID))
        }
    }

    func testMistakeInGermanLessonResetsPrefixedState() throws {
        let lesson = german.orderedLessons[0]
        play(lesson) // erst korrekt einschreiben

        // Danach eine Runde mit Fehlern: betroffene Karten werden zurückgesetzt.
        let session = LessonSession(mode: .lesson(lesson), content: german)
        while session.phase == .active, let exercise = session.current {
            session.record(outcome(for: exercise, correct: false))
            session.advance(context: context)
        }
        let mistakes = try context.fetch(FetchDescriptor<MistakeRecord>())
        XCTAssertFalse(mistakes.isEmpty)
        XCTAssertTrue(mistakes.allSatisfy { $0.lessonID.hasPrefix("de_") })

        // Fehler-Übung baut die Übungen über den Deutsch-Store wieder auf.
        let practice = LessonSession(mode: .mistakes(mistakes), content: german)
        XCTAssertFalse(practice.exercises.isEmpty)
    }

    // MARK: - Übungssemantik der Gegenrichtung

    func testVocabExercisesUseGermanAsTarget() throws {
        let lesson = german.orderedLessons[0]
        let factory = ExerciseFactory(content: german)
        let exercises = factory.exercises(for: lesson)

        // Produktions-Übungen fragen nach dem deutschen Wort.
        let production = exercises.compactMap { exercise -> MCExercise? in
            guard case .multipleChoice(let mc) = exercise.kind,
                  mc.instruction.contains("Deutsch") else { return nil }
            return mc
        }
        XCTAssertFalse(production.isEmpty, "Keine DE-Produktionsübungen gebaut")
        for mc in production {
            let item = german.vocabulary.first { $0.fr == mc.prompt }
            XCTAssertNotNil(item, "Prompt «\(mc.prompt)» sollte die französische Seite sein")
            XCTAssertEqual(mc.correctAnswer, item?.de)
        }
    }

    func testGermanConjugationExercisesBuild() throws {
        let factory = ExerciseFactory(content: german)
        let specs: [(String, Int, String?)] = [
            ("sein", 0, nil), ("aufstehen", 0, nil),
            ("machen", 0, "perfekt"), ("gehen", 0, "perfekt"),
            ("sein", 0, "praeteritum"), ("kommen", 1, "imperativ"),
        ]
        for (verb, person, tense) in specs {
            let spec = ExerciseSpec(type: .conjugation, verb: verb, person: person, tense: tense)
            let ref = ExerciseRef(lessonID: "test", exerciseIndex: 0, subIndex: 0)
            let exercise = factory.standaloneExercise(spec: spec, ref: ref)
            XCTAssertNotNil(exercise, "\(verb)/\(tense ?? "praesens") baut nicht")
        }
    }

    func testUmlautCountsAsAccentHint() {
        XCTAssertEqual(AnswerChecker.check(input: "du fahrst", answer: "du fährst"), .correctWithAccentHint)
        XCTAssertEqual(AnswerChecker.check(input: "ich heisse", answer: "ich heiße"), .correctWithAccentHint)
        XCTAssertEqual(AnswerChecker.check(input: "du fährst", answer: "du fährst"), .correct)
    }

    // MARK: - Prüfung & Hörtraining

    func testGermanExamsBuildAllQuestions() throws {
        for level in [CEFRLevel.a1, .a2] {
            let exam = try XCTUnwrap(german.examByLevel[level], "\(level.rawValue)-Prüfung fehlt")
            let session = ExamSession(exam: exam, content: german)
            XCTAssertEqual(session.direction, .german)
            XCTAssertEqual(session.questions.count, 30, "\(level.rawValue): alle 30 Fragen müssen baubar sein")
        }
    }

    func testMirroredPacksResolveAndPrefixCorrectly() throws {
        XCTAssertEqual(german.packs.count, 4, "Vier gespiegelte A2-Pakete")
        for pack in german.packs {
            XCTAssertTrue(pack.id.hasPrefix("de_pack_"))
            XCTAssertEqual(pack.level, .a2)
            for vocabID in pack.vocab {
                XCTAssertNotNil(german.vocab(vocabID), "\(pack.id): \(vocabID) fehlt")
            }
            // SRS-Einschreibung liefe über die de:-Präfix-IDs.
            let srsIDs = pack.vocab.map { german.srsID(for: $0) }
            XCTAssertTrue(srsIDs.allSatisfy { $0.hasPrefix("de:") })
        }
    }

    func testGermanListeningPoolAndPairs() {
        let trainer = ListeningTrainer(content: german)
        XCTAssertGreaterThanOrEqual(
            trainer.sentences(upTo: .a1).count, 20,
            "Der deutsche Satz-Pool braucht genug A1-Material"
        )
        // Zielseite ist Deutsch: Beispielsatz aus den Grammatikregeln.
        XCTAssertTrue(trainer.sentences.contains { $0.target == "Ich bin Anna." })

        let dictations = trainer.dictationExercises(upTo: .a1, count: 8)
        XCTAssertEqual(dictations.count, 8)

        XCTAssertGreaterThanOrEqual(german.minimalPairs.count, 20)
        let pairs = trainer.minimalPairExercises(count: 5)
        XCTAssertEqual(pairs.count, 5)
    }

    // MARK: - Richtungs-Umschaltung

    func testCertificatesAreScopedPerDirection() throws {
        let germanCert = EarnedCertificate(level: .a1, direction: .german, score: 80)
        let frenchCert = EarnedCertificate(level: .a1, direction: .french, score: 90)
        // Beide dürfen koexistieren — unterschiedliche levelRaw-Namensräume.
        XCTAssertNotEqual(germanCert.levelRaw, frenchCert.levelRaw)
        XCTAssertEqual(germanCert.level, frenchCert.level)
        XCTAssertEqual(germanCert.direction.examBrand(for: .a1), "Goethe-Zertifikat")
        XCTAssertEqual(frenchCert.direction.examBrand(for: .a1), "DELF")
    }

    func testUserSettingsDirectionRoundTrip() {
        let settings = UserSettings()
        XCTAssertEqual(settings.courseDirection, .french, "Bestandsnutzer bleiben im Französisch-Kurs")
        settings.courseDirection = .german
        XCTAssertEqual(settings.courseDirectionRaw, "de")
        XCTAssertEqual(settings.content.direction, .german)
    }
}
