import SwiftUI
import SwiftData

/// SRS-Session (Spec Screen 4): fällige Karten, Selbstbewertung mit vier
/// SM-2-Buttons, „Nochmal"-Karten kommen in derselben Session erneut.
struct ReviewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var states: [ReviewState]
    @Query private var settingsList: [UserSettings]

    @State private var queue: [ReviewState] = []
    @State private var built = false
    @State private var revealed = false
    @State private var reviewedCount = 0

    private let content = ContentStore.shared

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top, 12)

            if let state = queue.first, let item = content.vocab(state.vocabID) {
                cardView(state: state, item: item)
            } else if built {
                finishedView
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear(perform: build)
    }

    private func build() {
        guard !built else { return }
        built = true
        guard let settings = settingsList.first else { return }
        let q = SRSService.buildQueue(states: states, settings: settings)
        // Nur Karten, deren Vokabel es (noch) gibt.
        queue = q.all.filter { content.vocab($0.vocabID) != nil }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !queue.isEmpty {
                Text("Noch \(queue.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Karte

    private func cardView(state: ReviewState, item: VocabItem) -> some View {
        let production = state.repetitions >= 2 // DE→FR, sobald die Karte sitzt

        return VStack(spacing: 16) {
            Spacer()

            VStack(spacing: 14) {
                HStack {
                    Text(production ? "Deutsch → Französisch" : "Französisch → Deutsch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if state.isNew {
                        Text("NEU")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                    }
                }

                Text(production ? item.de : item.fr)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if !production, let detail = frontDetail(item) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if revealed {
                    Divider()
                    Text(production ? item.fr : item.de)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .multilineTextAlignment(.center)
                    if let example = item.exampleFR, let exampleDE = item.exampleDE {
                        VStack(spacing: 2) {
                            Text(example).font(.subheadline.italic())
                            Text(exampleDE).font(.footnote).foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                    }
                    if let note = item.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal)

            Spacer()

            bottomControls(state: state)
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
    }

    private func frontDetail(_ item: VocabItem) -> String? {
        var parts = [item.pos.germanLabel]
        if let gender = item.genderLabel { parts.append(gender) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func bottomControls(state: ReviewState) -> some View {
        if revealed {
            HStack(spacing: 8) {
                ForEach(ReviewGrade.allCases) { grade in
                    gradeButton(grade, state: state)
                }
            }
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { revealed = true }
            } label: {
                Text("Antwort zeigen")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func gradeButton(_ grade: ReviewGrade, state: ReviewState) -> some View {
        let days = SRSService.previewInterval(for: grade, state: state)
        return Button {
            apply(grade, to: state)
        } label: {
            VStack(spacing: 2) {
                Text(grade.label)
                    .font(.subheadline.bold())
                Text("\(days) T")
                    .font(.caption2)
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(gradeColor(grade))
    }

    private func gradeColor(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .again: return Theme.danger
        case .hard: return Theme.warning
        case .good: return Theme.success
        case .easy: return Theme.accent
        }
    }

    private func apply(_ grade: ReviewGrade, to state: ReviewState) {
        SRSService.apply(grade: grade, to: state, context: context)
        reviewedCount += 1
        revealed = false
        guard !queue.isEmpty else { return }
        let current = queue.removeFirst()
        if grade == .again {
            // In derselben Session erneut zeigen (Anki-Verhalten).
            queue.append(current)
        }
    }

    // MARK: - Abschluss

    private var finishedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: reviewedCount > 0 ? "checkmark.seal.fill" : "moon.zzz.fill")
                .font(.system(size: 56))
                .foregroundStyle(reviewedCount > 0 ? Theme.success : Theme.accent)
            Text(reviewedCount > 0 ? "Session beendet!" : "Keine Karten fällig")
                .font(.title2.bold())
            Text(reviewedCount > 0
                 ? "\(reviewedCount) \(reviewedCount == 1 ? "Bewertung" : "Bewertungen") — die nächsten Termine sind geplant."
                 : "Schau später wieder vorbei oder schließe eine neue Lektion ab.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                dismiss()
            } label: {
                Text("Fertig")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            Spacer()
        }
    }
}
