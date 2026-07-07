import XCTest
@testable import FrenchApp

/// Regelbasierter Konjugator: Gruppen 1/2 generiert, Orthografie-Regeln, Ausnahmentabelle.
final class ConjugatorTests: XCTestCase {
    private var content: ContentStore!

    override func setUpWithError() throws {
        content = try ContentStore(bundle: Bundle(for: ContentStore.self))
    }

    // MARK: Gruppe 1

    func testParlerPresent() throws {
        let verb = try XCTUnwrap(content.conjugator.verb("parler"))
        XCTAssertEqual(
            content.conjugator.presentForms(of: verb),
            ["parle", "parles", "parle", "parlons", "parlez", "parlent"]
        )
    }

    func testMangerInsertsEInNousForm() throws {
        let verb = try XCTUnwrap(content.conjugator.verb("manger"))
        XCTAssertEqual(content.conjugator.presentForms(of: verb)[3], "mangeons")
    }

    func testCommencerUsesCedilla() {
        // Nicht im Bundle-Inhalt — direkte Regelprüfung.
        XCTAssertEqual(Conjugator.firstGroupPresent(infinitive: "commencer")[3], "commençons")
    }

    func testAcheterStemChange() throws {
        let verb = try XCTUnwrap(content.conjugator.verb("acheter"))
        let forms = content.conjugator.presentForms(of: verb)
        XCTAssertEqual(forms[0], "achète")
        XCTAssertEqual(forms[3], "achetons") // nous ohne Stammwechsel
        XCTAssertEqual(forms[5], "achètent")
    }

    func testPrefererStemChange() {
        let forms = Conjugator.firstGroupPresent(infinitive: "préférer")
        XCTAssertEqual(forms[0], "préfère")
        XCTAssertEqual(forms[4], "préférez")
    }

    func testAppelerDoubling() {
        let forms = Conjugator.firstGroupPresent(infinitive: "appeler")
        XCTAssertEqual(forms[0], "appelle")
        XCTAssertEqual(forms[3], "appelons")
    }

    // MARK: Gruppe 2

    func testFinirPresent() throws {
        let verb = try XCTUnwrap(content.conjugator.verb("finir"))
        XCTAssertEqual(
            content.conjugator.presentForms(of: verb),
            ["finis", "finis", "finit", "finissons", "finissez", "finissent"]
        )
    }

    // MARK: Gruppe 3 (Ausnahmentabelle)

    func testEtreFromTable() throws {
        let verb = try XCTUnwrap(content.conjugator.verb("être"))
        XCTAssertEqual(
            content.conjugator.presentForms(of: verb),
            ["suis", "es", "est", "sommes", "êtes", "sont"]
        )
    }

    func testAllIrregularVerbsHaveSixPresentForms() {
        for verb in content.verbs where verb.group == 3 {
            XCTAssertEqual(verb.present?.count, 6, "\(verb.infinitive) braucht 6 Präsensformen")
        }
    }

    // MARK: Zusammengesetzte Zeiten

    func testPasseComposeWithAvoir() throws {
        let manger = try XCTUnwrap(content.conjugator.verb("manger"))
        XCTAssertEqual(content.conjugator.form(of: manger, tense: .passeCompose, person: 0), "ai mangé")
        let prendre = try XCTUnwrap(content.conjugator.verb("prendre"))
        XCTAssertEqual(content.conjugator.form(of: prendre, tense: .passeCompose, person: 2), "a pris")
    }

    func testPasseComposeWithEtreVerb() throws {
        // Seit Phase 2 unterstützt die Engine être-Verben (maskuline Grundform).
        let aller = try XCTUnwrap(content.conjugator.verb("aller"))
        XCTAssertEqual(content.conjugator.form(of: aller, tense: .passeCompose, person: 0), "suis allé")
    }

    func testFuturProche() throws {
        let visiter = try XCTUnwrap(content.conjugator.verb("visiter"))
        XCTAssertEqual(content.conjugator.form(of: visiter, tense: .futurProche, person: 3), "allons visiter")
    }

    func testParticiples() throws {
        let parler = try XCTUnwrap(content.conjugator.verb("parler"))
        XCTAssertEqual(content.conjugator.participle(of: parler), "parlé")
        let finir = try XCTUnwrap(content.conjugator.verb("finir"))
        XCTAssertEqual(content.conjugator.participle(of: finir), "fini")
    }

    // MARK: Elision

    func testElisionAfterJe() {
        XCTAssertTrue(Conjugator.elidesAfterJe("aime"))
        XCTAssertTrue(Conjugator.elidesAfterJe("habite"))
        XCTAssertTrue(Conjugator.elidesAfterJe("écoute"))
        XCTAssertFalse(Conjugator.elidesAfterJe("parle"))
        XCTAssertFalse(Conjugator.elidesAfterJe("vais"))
    }

    func testDisplayFormElision() throws {
        let aimer = try XCTUnwrap(content.conjugator.verb("aimer"))
        let table = content.conjugator.table(for: aimer)
        XCTAssertEqual(table[0].pronoun, "j'")
        XCTAssertEqual(table[0].form, "aime")
    }

    // MARK: Antwortbewertung

    func testAnswerCheckerExact() {
        XCTAssertEqual(AnswerChecker.check(input: " Parle ", answer: "parle"), .correct)
    }

    func testAnswerCheckerAccentHint() {
        XCTAssertEqual(AnswerChecker.check(input: "reponse", answer: "réponse"), .correctWithAccentHint)
        XCTAssertEqual(AnswerChecker.check(input: "etes", answer: "êtes"), .correctWithAccentHint)
    }

    func testAnswerCheckerApostropheNormalization() {
        XCTAssertEqual(AnswerChecker.check(input: "s’il vous plaît", answer: "s'il vous plaît"), .correct)
    }

    func testAnswerCheckerWrong() {
        XCTAssertEqual(AnswerChecker.check(input: "parles", answer: "parle"), .wrong)
    }
}
