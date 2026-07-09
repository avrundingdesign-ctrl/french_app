import SwiftUI
import SwiftData

/// Ersteinstieg ohne Reibung (Spec Screen 1): kein Login, Anfänger starten
/// automatisch bei A1. Abgefragt werden nur Kursrichtung und Tagespensum.
struct OnboardingView: View {
    @Bindable var settings: UserSettings
    @State private var page = 0
    @State private var pensum = 10
    /// Vorbelegt aus der Systemsprache: Frankophone lernen Deutsch.
    @State private var direction: CourseDirection =
        Locale.current.language.languageCode?.identifier == "fr" ? .german : .french

    private let lastPage = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                directionPage.tag(0)
                welcomePage.tag(1)
                methodPage.tag(2)
                pensumPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < lastPage {
                    withAnimation { page += 1 }
                } else {
                    settings.courseDirection = direction
                    settings.newCardsPerDay = pensum
                    settings.onboardingDone = true
                }
            } label: {
                Text(page < lastPage ? String(localized: "Weiter") : String(localized: "Los geht's!"))
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

    // MARK: - Kursrichtung

    private var directionPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "globe.europe.africa")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            Text("Was möchtest du lernen?")
                .font(.title.bold())
            Text("Wähle deine Lernsprache — die Erklärungen kommen in deiner Muttersprache.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                directionCard(
                    .french,
                    title: "Französisch lernen",
                    subtitle: "Ich spreche Deutsch · A1–B2"
                )
                directionCard(
                    .german,
                    title: "Apprendre l'allemand",
                    subtitle: "Je parle français · A1"
                )
            }
            .padding(.horizontal, 24)
            Spacer()
            Spacer()
        }
    }

    private func directionCard(_ candidate: CourseDirection, title: String, subtitle: String) -> some View {
        Button {
            direction = candidate
        } label: {
            HStack(spacing: 14) {
                Text(candidate.flag)
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: direction == candidate ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(direction == candidate ? Theme.accent : Color.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .stroke(direction == candidate ? Theme.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Info-Seiten

    private var welcomePage: some View {
        OnboardingPage(
            symbol: "book.fill",
            title: direction == .german ? "Willkommen ! Bienvenue !" : "Bienvenue !",
            text: direction == .german
                ? String(localized: "Deutsch lernen — Schritt für Schritt, komplett offline.\n\nDu startest ganz vorne: keine Vorkenntnisse nötig.")
                : String(localized: "Französisch lernen von A1 bis B2 — Schritt für Schritt, komplett offline.\n\nDu startest ganz vorne: keine Vorkenntnisse nötig.")
        )
    }

    private var methodPage: some View {
        OnboardingPage(
            symbol: "brain.head.profile",
            title: String(localized: "Ohne Druck, mit System"),
            text: String(localized: "Kurze Lektionen führen dich durch Vokabeln und Grammatik — mit Erklärungen in deiner Muttersprache.\n\nGelernte Wörter wiederholst du genau dann, wenn du sie zu vergessen drohst (Spaced Repetition).\n\nKeine Streaks, keine Ligen, keine Leben — nur dein Fortschritt zählt.")
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
