import XCTest
@testable import FrenchApp

/// Phase-2-Engine: Imparfait, Futur simple, Passé composé mit être, Reflexivverben.
final class ConjugatorPhase2Tests: XCTestCase {
    private var content: ContentStore!
    private var conjugator: Conjugator { content.conjugator }

    override func setUpWithError() throws {
        content = try ContentStore(bundle: Bundle(for: ContentStore.self))
    }

    // MARK: Imparfait

    func testImparfaitRegular() throws {
        let parler = try XCTUnwrap(conjugator.verb("parler"))
        XCTAssertEqual(
            conjugator.imparfaitForms(of: parler),
            ["parlais", "parlais", "parlait", "parlions", "parliez", "parlaient"]
        )
    }

    func testImparfaitOrthographyManger() throws {
        let manger = try XCTUnwrap(conjugator.verb("manger"))
        let forms = try XCTUnwrap(conjugator.imparfaitForms(of: manger))
        XCTAssertEqual(forms[0], "mangeais")   // e bleibt vor a
        XCTAssertEqual(forms[3], "mangions")   // e fällt vor i weg
        XCTAssertEqual(forms[4], "mangiez")
    }

    func testImparfaitEtreException() throws {
        let etre = try XCTUnwrap(conjugator.verb("être"))
        let forms = try XCTUnwrap(conjugator.imparfaitForms(of: etre))
        XCTAssertEqual(forms[0], "étais")
        XCTAssertEqual(forms[2], "était")
    }

    func testImparfaitStemFromNousForm() throws {
        let boire = try XCTUnwrap(conjugator.verb("boire"))
        XCTAssertEqual(conjugator.form(of: boire, tense: .imparfait, person: 0), "buvais")
        let faire = try XCTUnwrap(conjugator.verb("faire"))
        XCTAssertEqual(conjugator.form(of: faire, tense: .imparfait, person: 5), "faisaient")
    }

    // MARK: Futur simple

    func testFuturSimpleRegular() throws {
        let parler = try XCTUnwrap(conjugator.verb("parler"))
        XCTAssertEqual(conjugator.form(of: parler, tense: .futurSimple, person: 0), "parlerai")
        XCTAssertEqual(conjugator.form(of: parler, tense: .futurSimple, person: 3), "parlerons")
    }

    func testFuturSimpleDropsEForReVerbs() throws {
        let prendre = try XCTUnwrap(conjugator.verb("prendre"))
        XCTAssertEqual(conjugator.form(of: prendre, tense: .futurSimple, person: 2), "prendra")
        let vendre = try XCTUnwrap(conjugator.verb("vendre"))
        XCTAssertEqual(conjugator.form(of: vendre, tense: .futurSimple, person: 0), "vendrai")
    }

    func testFuturSimpleIrregularStems() throws {
        let expectations: [(String, String)] = [
            ("être", "serai"), ("avoir", "aurai"), ("aller", "irai"),
            ("faire", "ferai"), ("venir", "viendrai"), ("pouvoir", "pourrai"),
            ("vouloir", "voudrai"), ("devoir", "devrai"), ("voir", "verrai"),
        ]
        for (infinitive, expected) in expectations {
            let verb = try XCTUnwrap(conjugator.verb(infinitive))
            XCTAssertEqual(
                conjugator.form(of: verb, tense: .futurSimple, person: 0),
                expected, infinitive
            )
        }
    }

    func testFuturSimpleKeepsStemChange() throws {
        let acheter = try XCTUnwrap(conjugator.verb("acheter"))
        XCTAssertEqual(conjugator.form(of: acheter, tense: .futurSimple, person: 5), "achèteront")
    }

    // MARK: Passé composé mit être

    func testPasseComposeWithEtre() throws {
        let aller = try XCTUnwrap(conjugator.verb("aller"))
        XCTAssertEqual(conjugator.form(of: aller, tense: .passeCompose, person: 0), "suis allé")
        XCTAssertEqual(conjugator.form(of: aller, tense: .passeCompose, person: 3), "sommes allés")
        let partir = try XCTUnwrap(conjugator.verb("partir"))
        XCTAssertEqual(conjugator.form(of: partir, tense: .passeCompose, person: 2), "est parti")
        XCTAssertEqual(conjugator.form(of: partir, tense: .passeCompose, person: 5), "sont partis")
    }

    func testParticipleVariantsForAgreement() throws {
        let aller = try XCTUnwrap(conjugator.verb("aller"))
        XCTAssertEqual(Set(conjugator.participleVariants(of: aller, person: 0)), ["allé", "allée"])
        XCTAssertEqual(Set(conjugator.participleVariants(of: aller, person: 3)), ["allés", "allées"])
        XCTAssertEqual(
            Set(conjugator.participleVariants(of: aller, person: 4)),
            ["allé", "allée", "allés", "allées"]
        )
    }

    func testTableShowsAgreementForEtreVerbs() throws {
        let aller = try XCTUnwrap(conjugator.verb("aller"))
        let table = conjugator.table(for: aller, tense: .passeCompose)
        XCTAssertEqual(table[0].form, "suis allé(e)")
        XCTAssertEqual(table[3].form, "sommes allé(e)s")
        XCTAssertEqual(table[4].form, "êtes allé(e)(s)")
    }

    // MARK: Reflexive Verben

    func testReflexivePresent() throws {
        let seLever = try XCTUnwrap(conjugator.verb("se lever"))
        let forms = conjugator.presentForms(of: seLever)
        XCTAssertEqual(forms[0], "me lève")
        XCTAssertEqual(forms[1], "te lèves")
        XCTAssertEqual(forms[3], "nous levons")
        XCTAssertEqual(forms[5], "se lèvent")
    }

    func testReflexiveElision() throws {
        let shabiller = try XCTUnwrap(conjugator.verb("s'habiller"))
        XCTAssertEqual(conjugator.form(of: shabiller, tense: .present, person: 0), "m'habille")
        XCTAssertEqual(conjugator.form(of: shabiller, tense: .present, person: 2), "s'habille")
        XCTAssertEqual(conjugator.form(of: shabiller, tense: .present, person: 3), "nous habillons")
    }

    func testReflexiveImparfaitAndFutur() throws {
        let seLever = try XCTUnwrap(conjugator.verb("se lever"))
        XCTAssertEqual(conjugator.form(of: seLever, tense: .imparfait, person: 0), "me levais")
        XCTAssertEqual(conjugator.form(of: seLever, tense: .futurSimple, person: 0), "me lèverai")
    }

    func testReflexivePasseComposeSupported() throws {
        // Seit Phase 3 unterstützt: je me suis levé.
        let seLever = try XCTUnwrap(conjugator.verb("se lever"))
        XCTAssertEqual(conjugator.form(of: seLever, tense: .passeCompose, person: 0), "me suis levé")
    }

    // MARK: y → i (payer)

    func testPayerYToI() throws {
        let payer = try XCTUnwrap(conjugator.verb("payer"))
        let forms = conjugator.presentForms(of: payer)
        XCTAssertEqual(forms[0], "paie")
        XCTAssertEqual(forms[3], "payons")
        XCTAssertEqual(conjugator.form(of: payer, tense: .futurSimple, person: 0), "paierai")
    }

    // MARK: Antwortbewertung (Phase 2)

    func testCheckerIgnoresPunctuation() {
        XCTAssertEqual(AnswerChecker.check(input: "Tu verras", answer: "Tu verras !"), .correct)
        XCTAssertEqual(AnswerChecker.check(input: "je paie.", answer: "Je paie"), .correct)
    }

    func testTextInputAltAnswers() {
        let exercise = TextInputExercise(
            instruction: "", prefix: "", suffix: "",
            answer: "suis allé", altAnswers: ["suis allée"],
            hint: nil, translation: nil, fullSolution: "je suis allé"
        )
        XCTAssertEqual(exercise.check("suis allée"), .correct)
        XCTAssertEqual(exercise.check("suis alle"), .correctWithAccentHint)
        XCTAssertEqual(exercise.check("suis venu"), .wrong)
    }
}
