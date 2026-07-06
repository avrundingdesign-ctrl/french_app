import SwiftUI
import SwiftData

/// Ersteinstieg ohne Reibung (Spec Screen 1): kein Login, Anfänger starten
/// automatisch bei A1, nur das Tagespensum wird abgefragt.
struct OnboardingView: View {
    @Bindable var settings: UserSettings
    @State private var page = 0
    @State private var pensum = 10

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                methodPage.tag(1)
                pensumPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    settings.newCardsPerDay = pensum
                    settings.onboardingDone = true
                }
            } label: {
                Text(page < 2 ? "Weiter" : "Los geht's!")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var welcomePage: some View {
        OnboardingPage(
            symbol: "book.fill",
            title: "Bienvenue !",
            text: "Französisch lernen von A1 bis B2 — Schritt für Schritt, komplett offline.\n\nDu startest ganz vorne: keine Vorkenntnisse nötig."
        )
    }

    private var methodPage: some View {
        OnboardingPage(
            symbol: "brain.head.profile",
            title: "Ohne Druck, mit System",
            text: "Kurze Lektionen führen dich durch Vokabeln und Grammatik — mit Erklärungen auf Deutsch.\n\nGelernte Wörter wiederholst du genau dann, wenn du sie zu vergessen drohst (Spaced Repetition).\n\nKeine Streaks, keine Ligen, keine Leben — nur dein Fortschritt zählt."
        )
    }

    private var pensumPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            Text("Dein Tagespensum")
                .font(.title.bold())
            Text("Wie viele neue Wörter möchtest du pro Tag im Training dazunehmen? Du kannst das jederzeit in den Einstellungen ändern.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Picker("Tagespensum", selection: $pensum) {
                Text("Locker · 5").tag(5)
                Text("Solide · 10").tag(10)
                Text("Ambitioniert · 20").tag(20)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }
}

private struct OnboardingPage: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.title.bold())
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }
}
