import XCTest
import SwiftData
@testable import FrenchApp

/// Wortschatz-Pakete: Content-Integrität und SRS-Einspeisung.
@MainActor
final class PackTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var content: ContentStore!

    override func setUpWithError() throws {
        let schema = Schema([
            ReviewState.self, ReviewLogEntry.self, LessonProgress.self,
            MistakeRecord.self, UserSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
        content = try ContentStore(bundle: Bundle(for: ContentStore.self))
    }

    func testPacksReferenceExistingVocabWithoutLessonOverlap() {
        XCTAssertGreaterThanOrEqual(content.packs.count, 8)
        let lessonVocab = Set(content.orderedLessons.flatMap(\.newVocab))
        var seen = Set<String>()
        for pack in content.packs {
            XCTAssertGreaterThanOrEqual(pack.vocab.count, 15, pack.id)
            for vocabID in pack.vocab {
                XCTAssertNotNil(content.vocab(vocabID), "\(pack.id): \(vocabID) fehlt")
                XCTAssertFalse(lessonVocab.contains(vocabID), "\(pack.id): \(vocabID) schon in Lektion")
                XCTAssertTrue(seen.insert(vocabID).inserted, "\(pack.id): \(vocabID) doppelt")
            }
        }
    }

    func testPackVocabCarriesPackLevel() throws {
        let pack = try XCTUnwrap(content.packs.first { $0.id == "pack_b2_societe" })
        for vocabID in pack.vocab {
            XCTAssertEqual(
                content.vocabLevelByID[vocabID], .b2,
                "\(vocabID): Paket-Wort ohne Niveau — Profil-Statistik ginge daneben"
            )
        }
    }

    func testEnrollingPackFeedsSRSAndRespectsDailyQuota() throws {
        let settings = UserSettings()
        settings.newCardsPerDay = 10
        context.insert(settings)

        let pack = try XCTUnwrap(content.packs.first)
        SRSService.enroll(vocabIDs: pack.vocab, context: context)

        let states = SRSService.fetchStates(context: context)
        XCTAssertEqual(states.count, pack.vocab.count)
        XCTAssertTrue(states.allSatisfy(\.isNew))

        // Das Tagespensum deckelt die neuen Karten — kein Überfluten.
        let queue = SRSService.buildQueue(states: states, settings: settings)
        XCTAssertEqual(queue.fresh.count, 10)
        XCTAssertTrue(queue.due.isEmpty)

        // Doppeltes Aufnehmen erzeugt keine Duplikate.
        SRSService.enroll(vocabIDs: pack.vocab, context: context)
        XCTAssertEqual(SRSService.fetchStates(context: context).count, pack.vocab.count)
    }

    func testNewVerbsConjugateInAllTenses() throws {
        let newVerbs = [
            "courir", "dormir", "mourir", "naître", "suivre", "servir",
            "conduire", "traduire", "cuire", "rire", "plaire", "valoir",
            "craindre", "peindre", "suffire", "battre", "fuir", "mentir",
            "accueillir", "se taire",
        ]
        for infinitive in newVerbs {
            let verb = try XCTUnwrap(content.conjugator.verb(infinitive), "\(infinitive) fehlt")
            for tense in Conjugator.Tense.allCases {
                for person in 0...5 {
                    XCTAssertNotNil(
                        content.conjugator.form(of: verb, tense: tense, person: person),
                        "\(infinitive): keine Form für \(tense.rawValue), Person \(person)"
                    )
                }
            }
        }
        // Stichproben gegen bekannte Formen.
        let mourir = try XCTUnwrap(content.conjugator.verb("mourir"))
        XCTAssertEqual(content.conjugator.form(of: mourir, tense: .futurSimple, person: 2), "mourra")
        XCTAssertEqual(content.conjugator.form(of: mourir, tense: .passeCompose, person: 2), "est mort")
        XCTAssertEqual(content.conjugator.form(of: mourir, tense: .subjonctifPresent, person: 0), "meure")
        let craindre = try XCTUnwrap(content.conjugator.verb("craindre"))
        XCTAssertEqual(content.conjugator.form(of: craindre, tense: .imparfait, person: 3), "craignions")
        let valoir = try XCTUnwrap(content.conjugator.verb("valoir"))
        XCTAssertEqual(content.conjugator.form(of: valoir, tense: .conditionnel, person: 2), "vaudrait")
        XCTAssertEqual(content.conjugator.form(of: valoir, tense: .subjonctifPresent, person: 2), "vaille")
        let seTaire = try XCTUnwrap(content.conjugator.verb("se taire"))
        XCTAssertEqual(content.conjugator.form(of: seTaire, tense: .present, person: 0), "me tais")
        XCTAssertEqual(content.conjugator.form(of: seTaire, tense: .passeCompose, person: 0), "me suis tu")
    }

    func testNewGrammarRulesAreLinkedToLessons() {
        for ruleID in ["g_lequel", "g_subjonctif_passe", "g_mise_en_relief", "g_concordance", "g_ne_expletif"] {
            XCTAssertNotNil(content.grammarByID[ruleID], "\(ruleID) fehlt")
            XCTAssertFalse(
                content.lessons(covering: ruleID).isEmpty,
                "\(ruleID): hängt an keiner Lektion — wäre im Profil nie abgedeckt"
            )
        }
    }
}
