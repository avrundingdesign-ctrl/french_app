import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @AppStorage("appearance") private var appearance = "system"

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
        .task {
            let settings = settingsList.first ?? UserSettings.fetchOrCreate(in: context)
            // Dev-Flag für Screenshots/UI-Tests.
            if ProcessInfo.processInfo.arguments.contains("--skip-onboarding") {
                settings.onboardingDone = true
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
        return SRSService.dueCount(states: reviewStates, settings: settings)
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

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.fill") }
        }
    }
}
