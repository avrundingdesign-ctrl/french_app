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
            container = try ModelContainer(for: schema)
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
