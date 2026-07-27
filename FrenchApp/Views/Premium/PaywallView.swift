import SwiftUI

/// Paywall (Phase 6): Feature-Liste, Einmalkauf, Restore — kein Abo.
/// Wird als Sheet von allen Schloss-Badges aus geöffnet.
struct PaywallView: View {
    @EnvironmentObject private var premium: PremiumStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    VStack(alignment: .leading, spacing: 14) {
                        feature("rectangle.stack.fill", "Alle B2-Wortschatz-Pakete",
                                "10 fortgeschrittene Themenpakete — Politik, Wirtschaft, Kultur, Wissenschaft und mehr — mit hunderten zusätzlichen Wörtern fürs Training.")
                    }
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                    VStack(spacing: 12) {
                        purchaseButton

                        Button("Käufe wiederherstellen") {
                            Task { await premium.restore() }
                        }
                        .font(.subheadline)

                        Text("Einmalkauf — kein Abo. Mit Familienfreigabe teilbar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let error = premium.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Link("Datenschutzerklärung", destination: URL(string: "https://trin.studio/datenschutz.html")!)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: premium.isPremium) { _, nowPremium in
                if nowPremium { dismiss() }
            }
            .task {
                await premium.loadProduct()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("Premium freischalten")
                .font(.title2.bold())
            Text("Der komplette Lernpfad, alle Prüfungen und Vertiefungen sind kostenlos — Premium schaltet zusätzlich die B2-Wortschatz-Pakete frei.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var purchaseButton: some View {
        Button {
            Task { await premium.purchase() }
        } label: {
            HStack {
                if premium.isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else if let product = premium.product {
                    Text("Freischalten für \(product.displayPrice)")
                } else {
                    Text("Lade Preis …")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .disabled(premium.product == nil || premium.isPurchasing)
    }
}

// MARK: - Schloss-Badge

/// Kleines Premium-Schloss für gesperrte Zeilen (Lektionen, Pakete, Prüfungen).
struct PremiumBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.caption2)
            Text("Premium")
                .font(.caption2.bold())
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.accent.opacity(0.14), in: Capsule())
    }
}
