import XCTest
@testable import FrenchApp

/// Paywall-Gating: Lernpfad, Prüfungen und Vertiefungen sind komplett
/// kostenlos — Premium schaltet ausschließlich die B2-Wortschatz-Pakete frei.
final class PremiumTests: XCTestCase {
    // MARK: - Wortschatz-Pakete

    func testPacksUpToB1AreFree() {
        XCTAssertFalse(PremiumGate.packRequiresPremium(level: .a1))
        XCTAssertFalse(PremiumGate.packRequiresPremium(level: .a2))
        XCTAssertFalse(PremiumGate.packRequiresPremium(level: .b1))
    }

    func testB2PacksRequirePremium() {
        XCTAssertTrue(PremiumGate.packRequiresPremium(level: .b2))
    }

    // MARK: - Konsistenz mit dem Content

    /// Basis-Pakete (A1–B1) müssen frei bleiben; nur B2-Pakete sind Premium.
    func testFreeTierIsSubstantialInBothDirections() throws {
        for direction in CourseDirection.allCases {
            let content = try ContentStore(bundle: Bundle(for: ContentStore.self), direction: direction)

            let freePacks = content.packs.filter { !PremiumGate.packRequiresPremium(level: $0.level) }
            XCTAssertFalse(freePacks.isEmpty, "\(direction): Basis-Pakete (A1–B1) müssen frei bleiben")

            let premiumPacks = content.packs.filter { PremiumGate.packRequiresPremium(level: $0.level) }
            XCTAssertTrue(premiumPacks.allSatisfy { $0.level >= .b2 }, "\(direction): nur B2-Pakete sind Premium")
        }
    }
}
