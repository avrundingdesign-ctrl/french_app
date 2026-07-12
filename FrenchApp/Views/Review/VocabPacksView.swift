import SwiftUI
import SwiftData

/// Thematische Wortschatz-Pakete: auf Knopfdruck wandern alle Wörter eines
/// Pakets ins SRS-Training — das Tagespensum verteilt sie dann über die Tage.
struct VocabPacksView: View {
    @EnvironmentObject private var premium: PremiumStore
    @Query private var states: [ReviewState]
    @Query private var settingsList: [UserSettings]
    @State private var showPaywall = false

    private var content: ContentStore { settingsList.first?.content ?? .shared }

    /// Persistierte (ggf. richtungs-präfixierte) IDs der Trainingskarten.
    private var enrolledIDs: Set<String> {
        Set(states.map(\.vocabID))
    }

    private func isEnrolled(_ vocabID: String) -> Bool {
        enrolledIDs.contains(content.srsID(for: vocabID))
    }

    private func isPremiumLocked(_ pack: VocabPack) -> Bool {
        PremiumGate.packRequiresPremium(level: pack.level) && !premium.isPremium
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Jedes Paket erweitert dein Vokabeltraining um ein Themenfeld. Neue Wörter kommen nach und nach — dein Tagespensum bleibt gültig.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(levels, id: \.self) { level in
                    HStack {
                        LevelBadge(level: level)
                        Text(level.subtitle)
                            .font(.headline)
                    }
                    ForEach(content.packs.filter { $0.level == level }) { pack in
                        if isPremiumLocked(pack) {
                            Button {
                                showPaywall = true
                            } label: {
                                packRow(pack)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink {
                                VocabPackDetailView(pack: pack)
                            } label: {
                                packRow(pack)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Wortschatz-Pakete")
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private var levels: [CEFRLevel] {
        Array(Set(content.packs.map(\.level))).sorted()
    }

    private func packRow(_ pack: VocabPack) -> some View {
        let enrolled = pack.vocab.filter { isEnrolled($0) }.count
        let complete = enrolled == pack.vocab.count
        let locked = isPremiumLocked(pack)

        return HStack(spacing: 12) {
            Image(systemName: locked ? "crown.fill" : (pack.icon ?? "rectangle.stack"))
                .font(.title3)
                .frame(width: 34)
                .foregroundStyle(locked ? Theme.accent : (complete ? Theme.success : Theme.levelColor(pack.level)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pack.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(locked ? Color.secondary : Color.primary)
                    if locked {
                        PremiumBadge()
                    }
                }
                if let subtitle = pack.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(locked
                     ? "Mit Premium freischalten · \(pack.vocab.count) Wörter"
                     : complete
                        ? "Alle \(pack.vocab.count) Wörter im Training"
                        : enrolled > 0
                            ? "\(enrolled) von \(pack.vocab.count) Wörtern im Training"
                            : "\(pack.vocab.count) Wörter")
                    .font(.caption2)
                    .foregroundStyle(complete && !locked ? Theme.success : .secondary)
            }
            Spacer()
            if complete && !locked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Paket-Detail

struct VocabPackDetailView: View {
    let pack: VocabPack

    @EnvironmentObject private var premium: PremiumStore
    @Environment(\.modelContext) private var context
    @Query private var states: [ReviewState]
    @Query private var settingsList: [UserSettings]
    @State private var showPaywall = false

    private var content: ContentStore { settingsList.first?.content ?? .shared }

    private var premiumLocked: Bool {
        PremiumGate.packRequiresPremium(level: pack.level) && !premium.isPremium
    }

    private var items: [VocabItem] {
        pack.vocab.compactMap { content.vocab($0) }
    }

    private var enrolledIDs: Set<String> {
        Set(states.map(\.vocabID))
    }

    private var missing: [String] {
        pack.vocab.filter { !enrolledIDs.contains(content.srsID(for: $0)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let subtitle = pack.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if premiumLocked {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("Mit Premium freischalten", systemImage: "crown.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                } else if missing.isEmpty {
                    Label("Alle \(pack.vocab.count) Wörter sind in deinem Training", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.success)
                } else {
                    Button {
                        SRSService.enroll(vocabIDs: missing.map { content.srsID(for: $0) }, context: context)
                    } label: {
                        Label(
                            missing.count == pack.vocab.count
                                ? "Alle \(missing.count) Wörter ins Training aufnehmen"
                                : "Restliche \(missing.count) Wörter aufnehmen",
                            systemImage: "plus.circle.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.levelColor(pack.level))
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        wordRow(item)
                        if item.id != items.last?.id {
                            Divider()
                        }
                    }
                }
                .card()
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(pack.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private func wordRow(_ item: VocabItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fr)
                    .font(.body.weight(.medium))
                Text(item.de)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let example = item.exampleFR {
                    Text(example)
                        .font(.caption.italic())
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if enrolledIDs.contains(content.srsID(for: item.id)) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.success)
            }
        }
        .padding(.vertical, 8)
    }
}
