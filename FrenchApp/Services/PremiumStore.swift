import Foundation
import StoreKit

// MARK: - Gating-Regeln (Phase 6)

/// Was Premium kostet und was frei bleibt — bewusst als pure Logik getrennt
/// vom StoreKit-Teil, damit die Produktentscheidungen testbar sind.
/// Prinzip (ROADMAP Phase 6): Einstieg und Netzwerk frei, Tiefe kostet.
/// Frei: A1+A2-Lernpfad (beide Richtungen), A1/A2-Pakete, SRS-Trainer,
/// Hörtraining, Tandem, Prüfungen A1–B1. Premium: Lernpfad ab B1,
/// Wortschatzpakete ab B1, Vertiefungskapitel, Prüfungen ab B2.
enum PremiumGate {
    /// Lektionen ab B1 sind Premium (gilt für beide Kursrichtungen).
    static func lessonRequiresPremium(level: CEFRLevel) -> Bool {
        level >= .b1
    }

    /// Wortschatzpakete ab B1 sind Premium.
    static func packRequiresPremium(level: CEFRLevel) -> Bool {
        level >= .b1
    }

    /// Prüfungssimulationen B2/C1 sind Premium; A1–B1 bleiben frei.
    static func examRequiresPremium(level: CEFRLevel) -> Bool {
        level >= .b2
    }

    /// Vertiefungskapitel (optionale Komplex-Übungen) sind komplett Premium.
    static func challengeRequiresPremium(level: CEFRLevel) -> Bool {
        true
    }
}

// MARK: - StoreKit 2

/// Einmalkauf „Premium freischalten" (non-consumable, Familienfreigabe an).
/// Entitlement-Quelle ist `Transaction.currentEntitlements`; der Listener
/// auf `Transaction.updates` fängt Käufe von anderen Geräten und
/// Familienfreigabe ein. Dev-Flags `--premium` und `--unlock-all` schalten
/// für Reviews/Screenshots frei, ohne StoreKit anzufassen.
@MainActor
final class PremiumStore: ObservableObject {
    static let productID = "design.avrunding.frenchapp.premium"

    @Published private(set) var isPremium: Bool
    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing = false
    @Published var lastError: String?

    /// Dev-Override bleibt getrennt vom echten Entitlement, damit ein
    /// fehlgeschlagener Refresh das Flag nicht zurücksetzt.
    private let devOverride: Bool
    private var updatesTask: Task<Void, Never>?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        devOverride = arguments.contains("--premium") || arguments.contains("--unlock-all")
        isPremium = devOverride

        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await loadProduct()
            await refreshEntitlement()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProduct() async {
        guard product == nil else { return }
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            // Kein Netz o. Ä. — die Paywall zeigt dann einen Ladezustand;
            // erneuter Versuch beim nächsten Öffnen.
        }
    }

    func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        isPremium = entitled || devOverride
    }

    func purchase() async {
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Restore-Button (Apple-Pflicht): stößt den App-Store-Abgleich an
    /// und liest die Entitlements neu.
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlement()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        if transaction.productID == Self.productID {
            isPremium = transaction.revocationDate == nil || devOverride
        }
        await transaction.finish()
    }
}
