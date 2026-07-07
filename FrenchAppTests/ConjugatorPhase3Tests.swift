import XCTest
@testable import FrenchApp

/// Phase-3-Engine: Subjonctif, Conditionnel, Plus-que-parfait, Futur antérieur,
/// Conditionnel passé, reflexives Passé composé und Angleichung.
final class ConjugatorPhase3Tests: XCTestCase {
    private var content: ContentStore!
    private var conjugator: Conjugator { content.conjugator }

    override func setUpWithError() throws {
        content = try ContentStore(bundle: Bundle(for: ContentStore.self))
    }

    private func verb(_ infinitive: String) throws -> VerbEntry {
        try XCTUnwrap(conjugator.verb(infinitive), infinitive)
    }

    // MARK: Subjonctif présent

    func testSubjonctifRegularFromIlsStem() throws {
        XCTAssertEqual(
            conjugator.subjonctifForms(of: try verb("parler")),
            ["parle", "parles", "parle", "parlions", "parliez", "parlent"]
        )
        XCTAssertEqual(
            conjugator.subjonctifForms(of: try verb("finir"))?[0], "finisse"
        )
    }

    func testSubjonctifUsesIlsStemForBootVerbs() throws {
        // boire: ils boivent → que je boive, aber nous buvions (Imparfait-Form).
        let forms = try XCTUnwrap(conjugator.subjonctifForms(of: try verb("boire")))
        XCTAssertEqual(forms[0], "boive")
        XCTAssertEqual(forms[3], "buvions")
        let venir = try XCTUnwrap(conjugator.subjonctifForms(of: try verb("venir")))
        XCTAssertEqual(venir[1], "viennes")
        XCTAssertEqual(venir[3], "venions")
    }

    func testSubjonctifIrregularFromTable() throws {
        XCTAssertEqual(conjugator.form(of: try verb("être"), tense: .subjonctifPresent, person: 0), "sois")
        XCTAssertEqual(conjugator.form(of: try verb("avoir"), tense: .subjonctifPresent, person: 2), "ait")
        XCTAssertEqual(conjugator.form(of: try verb("aller"), tense: .subjonctifPresent, person: 0), "aille")
        XCTAssertEqual(conjugator.form(of: try verb("faire"), tense: .subjonctifPresent, person: 0), "fasse")
        XCTAssertEqual(conjugator.form(of: try verb("pouvoir"), tense: .subjonctifPresent, person: 3), "puissions")
        XCTAssertEqual(conjugator.form(of: try verb("savoir"), tense: .subjonctifPresent, person: 1), "saches")
    }

    func testSubjonctifTableUsesQuePronouns() throws {
        let table = conjugator.table(for: try verb("aller"), tense: .subjonctifPresent)
        XCTAssertEqual(table[0].pronoun, "que j'")
        XCTAssertEqual(table[2].pronoun, "qu'il/elle")
        XCTAssertEqual(table[3].pronoun, "que nous")
    }

    // MARK: Conditionnel

    func testConditionnelUsesFuturStemWithImparfaitEndings() throws {
        XCTAssertEqual(conjugator.form(of: try verb("aimer"), tense: .conditionnel, person: 0), "aimerais")
        XCTAssertEqual(conjugator.form(of: try verb("être"), tense: .conditionnel, person: 2), "serait")
        XCTAssertEqual(conjugator.form(of: try verb("pouvoir"), tense: .conditionnel, person: 1), "pourrais")
        XCTAssertEqual(conjugator.form(of: try verb("vouloir"), tense: .conditionnel, person: 0), "voudrais")
    }

    // MARK: Zusammengesetzte Zeiten

    func testPlusQueParfait() throws {
        XCTAssertEqual(conjugator.form(of: try verb("manger"), tense: .plusQueParfait, person: 0), "avais mangé")
        XCTAssertEqual(conjugator.form(of: try verb("partir"), tense: .plusQueParfait, person: 2), "était parti")
        XCTAssertEqual(conjugator.form(of: try verb("aller"), tense: .plusQueParfait, person: 3), "étions allés")
    }

    func testFuturAnterieur() throws {
        XCTAssertEqual(conjugator.form(of: try verb("finir"), tense: .futurAnterieur, person: 0), "aurai fini")
        XCTAssertEqual(conjugator.form(of: try verb("partir"), tense: .futurAnterieur, person: 2), "sera parti")
    }

    func testConditionnelPasse() throws {
        XCTAssertEqual(conjugator.form(of: try verb("devoir"), tense: .conditionnelPasse, person: 0), "aurais dû")
        XCTAssertEqual(conjugator.form(of: try verb("venir"), tense: .conditionnelPasse, person: 2), "serait venu")
    }

    // MARK: Reflexives Passé composé (seit Phase 3 unterstützt)

    func testReflexivePasseCompose() throws {
        XCTAssertEqual(conjugator.form(of: try verb("se lever"), tense: .passeCompose, person: 0), "me suis levé")
        XCTAssertEqual(conjugator.form(of: try verb("s'habiller"), tense: .passeCompose, person: 2), "s'est habillé")
        XCTAssertEqual(conjugator.form(of: try verb("se coucher"), tense: .passeCompose, person: 3), "nous sommes couchés")
        XCTAssertEqual(conjugator.form(of: try verb("se réveiller"), tense: .passeCompose, person: 5), "se sont réveillés")
    }

    func testReflexivePlusQueParfait() throws {
        XCTAssertEqual(conjugator.form(of: try verb("se lever"), tense: .plusQueParfait, person: 0), "m'étais levé")
    }

    func testReflexiveTableShowsAgreement() throws {
        let table = conjugator.table(for: try verb("se lever"), tense: .passeCompose)
        XCTAssertEqual(table[0].form, "me suis levé(e)")
        XCTAssertEqual(table[3].form, "nous sommes levé(e)s")
    }

    // MARK: Neue Verbmuster

    func testOffrirUsesErEndings() throws {
        let forms = conjugator.basePresentForms(of: try verb("offrir"))
        XCTAssertEqual(forms[0], "offre")
        XCTAssertEqual(forms[3], "offrons")
        XCTAssertEqual(conjugator.participle(of: try verb("offrir")), "offert")
    }

    func testProtegerCombinesAccentAndGe() throws {
        let forms = conjugator.basePresentForms(of: try verb("protéger"))
        XCTAssertEqual(forms[0], "protège")
        XCTAssertEqual(forms[3], "protégeons")
    }

    func testGroup3ReflexiveFromTable() throws {
        XCTAssertEqual(conjugator.form(of: try verb("se souvenir"), tense: .present, person: 0), "me souviens")
        XCTAssertEqual(conjugator.form(of: try verb("se sentir"), tense: .present, person: 1), "te sens")
    }
}
