import SwiftUI
import SwiftData

/// Profil & Statistik (Spec Screen 6): Fortschritt sichtbar machen —
/// bewusst ohne Streaks, Ligen oder Leaderboards.
struct ProfileView: View {
    @Query private var progress: [LessonProgress]
    @Query private var states: [ReviewState]
    @Query private var settingsList: [UserSettings]
    @Query private var mistakes: [MistakeRecord]

    private let content = ContentStore.shared

    private var snapshot: ProgressSnapshot {
        ProgressSnapshot(progress: progress, content: content)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    levelRings
                    statGrid
                    mistakeSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profil")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    // MARK: - Niveau-Ringe

    private var levelRings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Niveau-Fortschritt")
                .font(.headline)
            HStack(spacing: 16) {
                ForEach(CEFRLevel.allCases) { level in
                    let (done, total) = snapshot.levelProgress(level)
                    VStack(spacing: 8) {
                        ZStack {
                            ProgressRing(
                                progress: total > 0 ? Double(done) / Double(total) : 0,
                                color: Theme.levelColor(level),
                                lineWidth: 7
                            )
                            .frame(width: 62, height: 62)
                            Text(level.rawValue)
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.levelColor(level))
                        }
                        Text(total > 0 ? "\(done)/\(total)" : "bald")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .card()
    }

    // MARK: - Statistik

    private var statGrid: some View {
        let learned = states.filter { $0.repetitions >= 1 }.count
        let mature = states.filter(\.isMature).count
        let due = settingsList.first.map {
            SRSService.dueCount(states: states, settings: $0)
        } ?? 0

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(
                value: "\(states.count)",
                label: "Wörter im Training",
                symbol: "rectangle.stack",
                color: Theme.accent
            )
            StatTile(
                value: "\(learned)",
                label: "davon gelernt",
                symbol: "checkmark.circle",
                color: Theme.success
            )
            StatTile(
                value: "\(mature)",
                label: "gefestigt (21+ Tage)",
                symbol: "medal",
                color: Theme.warning
            )
            StatTile(
                value: "\(due)",
                label: "heute fällig",
                symbol: "clock",
                color: Theme.danger
            )
            StatTile(
                value: "\(progress.count)",
                label: "Lektionen abgeschlossen",
                symbol: "book.closed",
                color: Theme.levelColor(.a2)
            )
            StatTile(
                value: "\(snapshot.coveredGrammarCount)/\(content.grammarRules.count)",
                label: "Grammatikthemen",
                symbol: "text.book.closed",
                color: Theme.levelColor(.b2)
            )
        }
    }

    // MARK: - Fehler

    private var mistakeSection: some View {
        let unresolved = mistakes.filter { !$0.isResolved }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fehlerübersicht")
                    .font(.headline)
                Spacer()
                NavigationLink("Alle anzeigen") {
                    MistakesView()
                }
                .font(.subheadline)
            }
            if unresolved.isEmpty {
                Text("Keine offenen Fehler. Falsch beantwortete Übungen landen hier zum gezielten Üben.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(unresolved.sorted { $0.timestamp > $1.timestamp }.prefix(3), id: \.persistentModelID) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.prompt)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(record.correctAnswer)
                            .font(.caption)
                            .foregroundStyle(Theme.success)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .card()
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
