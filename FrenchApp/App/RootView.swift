import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @AppStorage("appearance") private var appearance = "system"
    /// Dev-Flag für Screenshots: öffnet die Paywall direkt beim Start.
    @State private var showPaywallDebug = ProcessInfo.processInfo.arguments.contains("--show-paywall")

    var body: some View {
        Group {
            if let settings = settingsList.first {
                if settings.onboardingDone {
                    MainTabView()
                } else {
                    OnboardingView(settings: settings)
                }
            } else {
                Color(.systemBackground)
            }
        }
        .sheet(isPresented: $showPaywallDebug) {
            PaywallView()
        }
        .task {
            let settings = settingsList.first ?? UserSettings.fetchOrCreate(in: context)
            // Dev-Flags für Screenshots/UI-Tests.
            if ProcessInfo.processInfo.arguments.contains("--skip-onboarding") {
                settings.onboardingDone = true
            }
            if ProcessInfo.processInfo.arguments.contains("--course-de") {
                settings.courseDirection = .german
            }
        }
        .preferredColorScheme(colorScheme)
        .tint(Theme.accent)
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

struct MainTabView: View {
    @Query private var reviewStates: [ReviewState]
    @Query private var settingsList: [UserSettings]

    private var dueCount: Int {
        guard let settings = settingsList.first else { return 0 }
        // Nur Karten der aktiven Kursrichtung zählen.
        let mine = reviewStates.filter { settings.courseDirection.owns(storageID: $0.vocabID) }
        return SRSService.dueCount(states: mine, settings: settings)
    }

    var body: some View {
        TabView {
            HomePathView()
                .tabItem { Label("Lernen", systemImage: "book.fill") }

            ReviewHubView()
                .tabItem { Label("Training", systemImage: "rectangle.stack.fill") }
                .badge(dueCount)

            GrammarListView()
                .tabItem { Label("Grammatik", systemImage: "text.book.closed.fill") }

            CommunityRootView()
                .tabItem { Label("Tandem", systemImage: "globe.europe.africa.fill") }

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.fill") }
        }
    }
}
