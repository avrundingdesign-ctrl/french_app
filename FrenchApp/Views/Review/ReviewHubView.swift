import SwiftUI
import SwiftData

/// Einstieg ins tägliche Training: fällige SRS-Karten und Fehlerwiederholung.
struct ReviewHubView: View {
    @Query private var states: [ReviewState]
    @Query private var settingsList: [UserSettings]
    @Query private var mistakes: [MistakeRecord]

    @State private var showSession = false
    @State private var showMistakePractice = false
    @State private var listeningMode: ListeningTrainer.Mode?
    @AppStorage("listeningLevel") private var listeningLevelRaw = CEFRLevel.a1.rawValue

    private let content = ContentStore.shared

    private var queue: SRSService.Queue {
        guard let settings = settingsList.first else {
            return SRSService.Queue(due: [], fresh: [])
        }
        return SRSService.buildQueue(states: states, settings: settings)
    }

    private var unresolvedMistakes: [MistakeRecord] {
        mistakes.filter { !$0.isResolved }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    reviewCard
                    mistakeCard
                    listeningCard
                    infoCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Training")
            .fullScreenCover(isPresented: $showSession) {
                ReviewSessionView()
            }
            .fullScreenCover(isPresented: $showMistakePractice) {
                LessonSessionView(mode: .mistakes(unresolvedMistakes))
            }
            .fullScreenCover(item: $listeningMode) { mode in
                ListeningSessionView(mode: mode, level: listeningLevel)
            }
        }
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Vokabeltraining", systemImage: "rectangle.stack.fill")
                .font(.headline)

            if queue.isEmpty {
                Text(states.isEmpty
                     ? "Schließe deine erste Lektion ab, dann landen neue Wörter hier im Training."
                     : "Alles erledigt! Zurzeit ist keine Karte fällig.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let next = nextDueDate {
                    Text("Nächste Wiederholung: \(next.formatted(date: .abbreviated, time: .omitted))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 20) {
                    countBlock(value: queue.due.count, label: "fällig", color: Theme.warning)
                    countBlock(value: queue.fresh.count, label: "neu", color: Theme.accent)
                }
                Button {
                    showSession = true
                } label: {
                    Text("Training starten")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var mistakeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Fehler üben", systemImage: "arrow.counterclockwise")
                .font(.headline)

            if unresolvedMistakes.isEmpty {
                Text("Keine offenen Fehler — stark!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(unresolvedMistakes.count) \(unresolvedMistakes.count == 1 ? "Übung wartet" : "Übungen warten") auf eine zweite Chance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    showMistakePractice = true
                } label: {
                    Text("Fehler üben")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(Theme.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Hörtraining

    private var listeningLevel: CEFRLevel {
        CEFRLevel(rawValue: listeningLevelRaw) ?? .a1
    }

    /// Niveaus mit Lektionen — C1 hat keine Beispielsätze im Pool.
    private var listeningLevels: [CEFRLevel] {
        content.levels
    }

    private var listeningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Hörtraining", systemImage: "ear")
                .font(.headline)

            Text("Trainiere dein Ohr mit der französischen Sprachausgabe — die beste Vorbereitung auf das Hörverstehen der Niveau-Prüfungen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Niveau", selection: $listeningLevelRaw) {
                ForEach(listeningLevels) { level in
                    Text(level.rawValue).tag(level.rawValue)
                }
            }
            .pickerStyle(.segmented)

            ForEach(ListeningTrainer.Mode.allCases) { mode in
                Button {
                    listeningMode = mode
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mode.symbol)
                            .frame(width: 28)
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mode.germanTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.primary)
                            Text(mode.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("So funktioniert's", systemImage: "info.circle")
                .font(.subheadline.bold())
            Text("Nach jeder Karte bewertest du selbst, wie gut du dich erinnert hast. Daraus berechnet die App den optimalen Zeitpunkt für die nächste Wiederholung (SM-2-Algorithmus) — je sicherer du bist, desto seltener siehst du die Karte.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func countBlock(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var nextDueDate: Date? {
        states
            .filter { !$0.isNew }
            .map(\.nextReview)
            .filter { $0 > .now }
            .min()
    }
}
