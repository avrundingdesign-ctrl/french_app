import XCTest
@testable import FrenchApp

/// Deutscher Konjugator (Phase 5a): Regelgenerierung für schwache Verben,
/// Overrides für starke/gemischte/unregelmäßige, trennbare Verben,
/// Perfekt mit haben/sein — getestet gegen die echte verbs_de.json.
final class GermanConjugatorTests: XCTestCase {
    private var content: ContentStore!
    private var conjugator: GermanConjugator!

    override func setUpWithError() throws {
        content = try ContentStore(bundle: Bundle(for: ContentStore.self), direction: .german)
        conjugator = content.germanConjugator
    }

    private func verb(_ infinitive: String) throws -> GermanVerbEntry {
        try XCTUnwrap(conjugator.verb(infinitive), "\(infinitive) fehlt in verbs_de.json")
    }

    private func form(_ infinitive: String, _ tense: GermanConjugator.Tense, _ person: Int) throws -> String {
        try XCTUnwrap(
            conjugator.form(of: verb(infinitive), tense: tense, person: person),
            "\(infinitive)/\(tense.rawValue)/P\(person) liefert keine Form"
        )
    }

    // MARK: - Invarianten über alle Verben

    func testAllVerbsProduceSixPresentForms() throws {
        for entry in conjugator.verbs {
            for person in 0...5 {
                XCTAssertNotNil(
                    conjugator.form(of: entry, tense: .praesens, person: person),
                    "\(entry.infinitive): Präsens P\(person) fehlt"
                )
            }
        }
    }

    func testStrongAndMixedVerbsAlwaysHaveExplicitParticiple() throws {
        for entry in conjugator.verbs where ["strong", "mixed"].contains(entry.type) {
            XCTAssertNotNil(entry.participle, "\(entry.infinitive): starkes/gemischtes Verb ohne Partizip")
        }
    }

    func testSeparablePrefixesArePrefixesOfTheInfinitive() throws {
        for entry in conjugator.verbs {
            if let prefix = entry.separablePrefix {
                // Reflexive tragen "sich " vor dem eigentlichen Infinitiv.
                let bare = entry.infinitive.hasPrefix("sich ")
                    ? String(entry.infinitive.dropFirst(5))
                    : entry.infinitive
                XCTAssertTrue(bare.hasPrefix(prefix), entry.infinitive)
            }
        }
    }

    // MARK: - Präsens

    func testWeakPresent() throws {
        XCTAssertEqual(try form("machen", .praesens, 0), "mache")
        XCTAssertEqual(try form("machen", .praesens, 1), "machst")
        XCTAssertEqual(try form("machen", .praesens, 3), "machen")
    }

    func testEpenthesisInWeakPresent() throws {
        XCTAssertEqual(try form("arbeiten", .praesens, 1), "arbeitest")
        XCTAssertEqual(try form("arbeiten", .praesens, 2), "arbeitet")
        XCTAssertEqual(try form("öffnen", .praesens, 1), "öffnest")
        XCTAssertEqual(try form("regnen", .praesens, 2), "regnet")
        XCTAssertEqual(try form("atmen", .praesens, 1), "atmest")
        // Kein Epenthese-Fehlgriff bei r/h vor n:
        XCTAssertEqual(try form("lernen", .praesens, 1), "lernst")
        XCTAssertEqual(try form("wohnen", .praesens, 1), "wohnst")
    }

    func testSContractionInSecondPerson() throws {
        XCTAssertEqual(try form("reisen", .praesens, 1), "reist")
        XCTAssertEqual(try form("tanzen", .praesens, 1), "tanzt")
        XCTAssertEqual(try form("heißen", .praesens, 1), "heißt")
    }

    func testStrongVowelChange() throws {
        XCTAssertEqual(try form("fahren", .praesens, 1), "fährst")
        XCTAssertEqual(try form("fahren", .praesens, 2), "fährt")
        XCTAssertEqual(try form("fahren", .praesens, 0), "fahre", "1. Person ohne Umlaut")
        XCTAssertEqual(try form("essen", .praesens, 1), "isst", "s-Kontraktion auf Wechselstamm")
        XCTAssertEqual(try form("essen", .praesens, 2), "isst")
        XCTAssertEqual(try form("lesen", .praesens, 1), "liest")
        XCTAssertEqual(try form("nehmen", .praesens, 2), "nimmt")
    }

    func testSeparableVerbsSplitInPresent() throws {
        XCTAssertEqual(try form("aufstehen", .praesens, 0), "stehe auf")
        XCTAssertEqual(try form("einkaufen", .praesens, 2), "kauft ein")
        XCTAssertEqual(try form("fernsehen", .praesens, 2), "sieht fern")
        XCTAssertEqual(try form("einladen", .praesens, 1), "lädst ein")
        XCTAssertEqual(try form("einladen", .praesens, 2), "lädt ein")
    }

    func testIrregularAndModalPresentComeFromTable() throws {
        XCTAssertEqual(try form("sein", .praesens, 0), "bin")
        XCTAssertEqual(try form("sein", .praesens, 4), "seid")
        XCTAssertEqual(try form("wissen", .praesens, 2), "weiß")
        XCTAssertEqual(try form("können", .praesens, 0), "kann")
        XCTAssertEqual(try form("möchten", .praesens, 1), "möchtest")
        XCTAssertEqual(try form("werden", .praesens, 1), "wirst")
    }

    func testEelnErnVerbs() throws {
        XCTAssertEqual(try form("wandern", .praesens, 0), "wandere")
        XCTAssertEqual(try form("wandern", .praesens, 3), "wandern")
        XCTAssertEqual(try form("feiern", .praesens, 2), "feiert")
    }

    // MARK: - Perfekt

    func testPerfektWithHaben() throws {
        XCTAssertEqual(try form("arbeiten", .perfekt, 0), "habe gearbeitet")
        XCTAssertEqual(try form("kaufen", .perfekt, 2), "hat gekauft")
        XCTAssertEqual(try form("essen", .perfekt, 3), "haben gegessen")
    }

    func testPerfektWithSein() throws {
        XCTAssertEqual(try form("aufstehen", .perfekt, 0), "bin aufgestanden")
        XCTAssertEqual(try form("kommen", .perfekt, 2), "ist gekommen")
        XCTAssertEqual(try form("reisen", .perfekt, 3), "sind gereist")
    }

    func testParticipleWithoutGePrefix() throws {
        XCTAssertEqual(try form("telefonieren", .perfekt, 2), "hat telefoniert")
        XCTAssertEqual(try form("besuchen", .perfekt, 0), "habe besucht")
        XCTAssertEqual(try form("erklären", .perfekt, 1), "hast erklärt")
        XCTAssertEqual(try form("wiederholen", .perfekt, 2), "hat wiederholt")
    }

    func testSeparableParticiple() throws {
        XCTAssertEqual(try form("einkaufen", .perfekt, 0), "habe eingekauft")
        XCTAssertEqual(try form("anrufen", .perfekt, 2), "hat angerufen")
        XCTAssertEqual(try form("aufräumen", .perfekt, 1), "hast aufgeräumt")
    }

    // MARK: - Präteritum (nur Tabellenverben)

    func testPraeteritumForTableVerbs() throws {
        XCTAssertEqual(try form("sein", .praeteritum, 0), "war")
        XCTAssertEqual(try form("haben", .praeteritum, 1), "hattest")
        XCTAssertEqual(try form("können", .praeteritum, 0), "konnte")
        XCTAssertEqual(try form("müssen", .praeteritum, 3), "mussten")
    }

    func testNoPraeteritumOutsideTheTable() throws {
        XCTAssertNil(conjugator.form(of: try verb("machen"), tense: .praeteritum, person: 0))
        XCTAssertNil(conjugator.form(of: try verb("fahren"), tense: .praeteritum, person: 2))
    }

    // MARK: - Imperativ

    func testImperative() throws {
        XCTAssertEqual(try form("kommen", .imperativ, 1), "komm")
        XCTAssertEqual(try form("arbeiten", .imperativ, 1), "arbeite")
        XCTAssertEqual(try form("öffnen", .imperativ, 1), "öffne")
        XCTAssertEqual(try form("kommen", .imperativ, 4), "kommt")
        XCTAssertEqual(try form("kommen", .imperativ, 5), "kommen Sie")
        XCTAssertEqual(try form("fahren", .imperativ, 1), "fahr", "Kein Umlaut im Imperativ")
    }

    func testIrregularImperativeFromTable() throws {
        XCTAssertEqual(try form("essen", .imperativ, 1), "iss")
        XCTAssertEqual(try form("sein", .imperativ, 1), "sei")
        XCTAssertEqual(try form("sein", .imperativ, 5), "seien Sie")
    }

    func testSeparableImperative() throws {
        XCTAssertEqual(try form("aufstehen", .imperativ, 1), "steh auf")
        XCTAssertEqual(try form("einkaufen", .imperativ, 5), "kaufen Sie ein")
    }

    func testModalsHaveNoImperative() throws {
        XCTAssertNil(conjugator.form(of: try verb("können"), tense: .imperativ, person: 1))
    }

    func testImperativeOnlyForDuIhrSie() throws {
        XCTAssertNil(conjugator.form(of: try verb("kommen"), tense: .imperativ, person: 0))
        XCTAssertNil(conjugator.form(of: try verb("kommen"), tense: .imperativ, person: 3))
    }

    // MARK: - Futur (A2)

    func testFutur() throws {
        XCTAssertEqual(try form("arbeiten", .futur, 0), "werde arbeiten")
        XCTAssertEqual(try form("kommen", .futur, 1), "wirst kommen")
        XCTAssertEqual(try form("aufstehen", .futur, 2), "wird aufstehen", "Trennbares Verb bleibt im Futur ganz")
        XCTAssertEqual(try form("sein", .futur, 3), "werden sein")
    }

    // MARK: - Reflexive Verben (A2)

    func testReflexivePresent() throws {
        XCTAssertEqual(try form("sich waschen", .praesens, 0), "wasche mich")
        XCTAssertEqual(try form("sich waschen", .praesens, 1), "wäschst dich")
        XCTAssertEqual(try form("sich freuen", .praesens, 2), "freut sich")
        XCTAssertEqual(try form("sich anziehen", .praesens, 0), "ziehe mich an", "Reflexiv + trennbar")
        XCTAssertEqual(try form("sich ausruhen", .praesens, 3), "ruhen uns aus")
    }

    func testReflexivePerfektAndFutur() throws {
        XCTAssertEqual(try form("sich waschen", .perfekt, 0), "habe mich gewaschen")
        XCTAssertEqual(try form("sich freuen", .perfekt, 2), "hat sich gefreut")
        XCTAssertEqual(try form("sich beeilen", .perfekt, 1), "hast dich beeilt", "be-Präfix ohne ge-")
        XCTAssertEqual(try form("sich anziehen", .perfekt, 0), "habe mich angezogen")
        XCTAssertEqual(try form("sich waschen", .futur, 0), "werde mich waschen")
    }

    func testReflexiveImperative() throws {
        XCTAssertEqual(try form("sich waschen", .imperativ, 1), "wasch dich")
        XCTAssertEqual(try form("sich beeilen", .imperativ, 5), "beeilen Sie sich")
        XCTAssertEqual(try form("sich anziehen", .imperativ, 1), "zieh dich an")
    }

    func testNewA2Verbs() throws {
        XCTAssertEqual(try form("einsteigen", .praesens, 0), "steige ein")
        XCTAssertEqual(try form("umsteigen", .perfekt, 1), "bist umgestiegen")
        XCTAssertEqual(try form("gefallen", .praesens, 2), "gefällt")
        XCTAssertEqual(try form("vergessen", .praesens, 1), "vergisst")
        XCTAssertEqual(try form("wehtun", .praesens, 2), "tut weh")
        XCTAssertEqual(try form("wehtun", .perfekt, 2), "hat wehgetan")
        XCTAssertEqual(try form("kennenlernen", .perfekt, 0), "habe kennengelernt")
        XCTAssertEqual(try form("gehören", .perfekt, 2), "hat gehört", "ge-Präfix: kein doppeltes ge-")
        XCTAssertEqual(try form("passieren", .perfekt, 2), "ist passiert")
        XCTAssertEqual(try form("anprobieren", .perfekt, 0), "habe anprobiert")
    }

    // MARK: - Tabellen & verfügbare Tempora

    func testTableAndAvailableTenses() throws {
        let machen = try verb("machen")
        let table = conjugator.table(for: machen, tense: .praesens)
        XCTAssertEqual(table.count, 6)
        XCTAssertEqual(table[0].pronoun, "ich")
        XCTAssertEqual(table[0].form, "mache")

        let tenses = conjugator.availableTenses(for: machen)
        XCTAssertTrue(tenses.contains(.praesens))
        XCTAssertTrue(tenses.contains(.perfekt))
        XCTAssertTrue(tenses.contains(.imperativ))
        XCTAssertFalse(tenses.contains(.praeteritum), "machen hat keine A1-Präteritumtabelle")

        let imperativeTable = conjugator.table(for: machen, tense: .imperativ)
        XCTAssertEqual(imperativeTable.count, 3)
    }

    // MARK: - Richtungs-Fundament (WP1)

    func testGermanStoreLoadsOwnContentSet() throws {
        XCTAssertEqual(content.direction, .german)
        XCTAssertFalse(content.germanVerbs.isEmpty)
        XCTAssertTrue(content.verbs.isEmpty, "Französische Verben gehören nicht in den Deutsch-Store")
        XCTAssertFalse(content.vocabulary.isEmpty, "Vokabeln werden geteilt")
    }

    func testReviewIDPrefixRoundTrip() throws {
        XCTAssertEqual(content.srsID(for: "v_bonjour"), "de:v_bonjour")
        let french = try ContentStore(bundle: Bundle(for: ContentStore.self), direction: .french)
        XCTAssertEqual(french.srsID(for: "v_bonjour"), "v_bonjour")

        // Auflösung filtert die jeweils fremde Richtung aus.
        if let anyVocab = content.vocabulary.first {
            let prefixed = content.srsID(for: anyVocab.id)
            XCTAssertEqual(content.vocab(forReviewID: prefixed)?.id, anyVocab.id)
            XCTAssertNil(french.vocab(forReviewID: prefixed))
            XCTAssertNil(content.vocab(forReviewID: anyVocab.id))
            XCTAssertEqual(french.vocab(forReviewID: anyVocab.id)?.id, anyVocab.id)
        }
    }

    func testCertificateAndAttemptCarryDirection() throws {
        let certificate = EarnedCertificate(level: .a1, direction: .german, score: 80)
        XCTAssertEqual(certificate.levelRaw, "de:A1")
        XCTAssertEqual(certificate.level, .a1)
        XCTAssertEqual(certificate.direction, .german)
        XCTAssertTrue(certificate.serial.hasPrefix("DE-A1-"))

        let legacy = EarnedCertificate(level: .b1, score: 70)
        XCTAssertEqual(legacy.levelRaw, "B1", "Bestandsformat bleibt unpräfixiert")
        XCTAssertEqual(legacy.level, .b1)
        XCTAssertEqual(legacy.direction, .french)
    }

    func testLanguagePairFlipsSides() throws {
        let item = try XCTUnwrap(content.vocabulary.first)
        let germanPair = content.pair
        XCTAssertEqual(germanPair.target(item), item.de)
        XCTAssertEqual(germanPair.native(item), item.fr)
        let frenchPair = LanguagePair(direction: .french)
        XCTAssertEqual(frenchPair.target(item), item.fr)
        XCTAssertEqual(frenchPair.native(item), item.de)
    }
}
