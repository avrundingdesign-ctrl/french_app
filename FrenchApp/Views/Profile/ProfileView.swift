import SwiftUI
import SwiftData

/// Profil & Statistik (Spec Screen 6): Fortschritt sichtbar machen —
/// bewusst ohne Streaks, Ligen oder Leaderboards.
struct ProfileView: View {
    @Query private var progress: [LessonProgress]
    @Query private var states: [ReviewState]
    @Query private var settingsList: [UserSettings]
    @Query private var mistakes: [MistakeRecord]
    @Query private var reviewLog: [ReviewLogEntry]
    @Query private var certificates: [EarnedCertificate]

    private let content = ContentStore.shared

    private var snapshot: ProgressSnapshot {
        ProgressSnapshot(progress: progress, content: content)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    levelRings
                    certificateSection
                    statGrid
                    forecastSection
                    activitySection
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

    // MARK: - Fälligkeits-Prognose (nächste 7 Tage)

    private var forecastSection: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days: [(label: String, count: Int)] = (0..<7).map { offset in
            let dayStart = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let count = states.filter {
                !$0.isNew && (offset == 0 ? $0.nextReview < dayEnd : ($0.nextReview >= dayStart && $0.nextReview < dayEnd))
            }.count
            let label = offset == 0 ? "heute" : dayStart.formatted(.dateTime.weekday(.abbreviated))
            return (label, count)
        }
        let maxCount = max(days.map(\.count).max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Wiederholungen — nächste 7 Tage")
                .font(.headline)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(days.indices, id: \.self) { index in
                    VStack(spacing: 4) {
                        Text("\(days[index].count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(index == 0 ? Theme.warning : Theme.accent.opacity(0.55))
                            .frame(height: max(4, CGFloat(days[index].count) / CGFloat(maxCount) * 56))
                        Text(days[index].label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .card()
    }

    // MARK: - Aktivität & Wörter nach Niveau

    private var activitySection: some View {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        let reviewsThisWeek = reviewLog.filter { $0.timestamp >= weekAgo }.count

        return VStack(alignment: .leading, spacing: 10) {
            Text("Training")
                .font(.headline)
            HStack {
                statInline(value: "\(reviewLog.count)", label: "Bewertungen gesamt")
                Divider().frame(height: 32)
                statInline(value: "\(reviewsThisWeek)", label: "in den letzten 7 Tagen")
            }
            Divider()
            ForEach(content.levels) { level in
                let ids = Set(states.map(\.vocabID))
                let count = ids.filter { content.vocabLevelByID[$0] == level }.count
                let total = content.vocabLevelByID.values.filter { $0 == level }.count
                HStack {
                    LevelBadge(level: level)
                    Text("Wörter im Training")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(count)/\(total)")
                        .font(.subheadline.monospacedDigit())
                }
            }
        }
        .card()
    }

    private func statInline(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Zertifikate

    private var certificateSection: some View {
        let earned = Set(certificates.compactMap(\.level))
        let examLevels = content.exams.map(\.level).sorted()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Zertifikate")
                    .font(.headline)
                Spacer()
                NavigationLink("Galerie") {
                    CertificateGalleryView()
                }
                .font(.subheadline)
            }
            HStack(spacing: 16) {
                ForEach(examLevels) { level in
                    VStack(spacing: 6) {
                        ZStack {
                            Image(systemName: earned.contains(level) ? "seal.fill" : "seal")
                                .font(.system(size: 44))
                                .foregroundStyle(
                                    earned.contains(level)
                                        ? AnyShapeStyle(Theme.levelColor(level).gradient)
                                        : AnyShapeStyle(Color(.systemFill))
                                )
                            Text(level.rawValue)
                                .font(.caption.bold())
                                .foregroundStyle(earned.contains(level) ? .white : .secondary)
                        }
                        Text(earned.contains(level) ? "bestanden" : "offen")
                            .font(.caption2)
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
