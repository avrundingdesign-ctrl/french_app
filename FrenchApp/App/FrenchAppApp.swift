import SwiftUI
import SwiftData

@main
struct FrenchAppApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([
            ReviewState.self,
            ReviewLogEntry.self,
            LessonProgress.self,
            MistakeRecord.self,
            UserSettings.self,
            ExamAttempt.self,
            EarnedCertificate.self,
            ChallengeProgress.self,
        ])
        do {
            // Lernfortschritt bleibt lokal: Die iCloud-Entitlements gehören der
            // Tandem-Community (direktes CloudKit) — ohne .none würde SwiftData
            // sonst automatisch CloudKit-Sync aktivieren und an den
            // unique-Constraints (ReviewState.vocabID …) scheitern.
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("SwiftData-Container konnte nicht erstellt werden: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
