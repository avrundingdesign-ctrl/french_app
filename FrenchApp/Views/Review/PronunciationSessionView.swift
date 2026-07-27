import SwiftUI

/// Sprechtraining: Wort oder Satz anhören, nachsprechen, Bewertung sehen.
/// Übungsmodus ohne Prüfungsdruck — beliebig viele Versuche pro Aufgabe.
struct PronunciationSessionView: View {
    let mode: PronunciationTrainer.Mode
    let level: CEFRLevel
    var content: ContentStore = .shared

    @Environment(\.dismiss) private var dismiss
    @State private var service = PronunciationService()
    @State private var items: [PronunciationTrainer.Item] = []
    @State private var built = false
    @State private var index = 0
    @State private var assessment: PronunciationScorer.Assessment?
    /// Beste Bewertung pro Aufgabe — zählt für die Bilanz am Ende.
    @State private var bestScores: [String: Double] = [:]
    @State private var accessGranted: Bool?

    private static let itemCount = 8

    private var language: String { content.direction.targetLocaleID }

    private var current: PronunciationTrainer.Item? {
        items.indices.contains(index) ? items[index] : nil
    }

    var body: some View {
        Group {
            if accessGranted == false || service.status == .denied {
                deniedView
            } else if service.status == .unavailable {
                unavailableView
            } else if let item = current {
                activeView(item)
            } else if built {
                finishedView
            }
        }
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
        .task {
            guard !built else { return }
            built = true
            items = PronunciationTrainer(content: content)
                .items(mode: mode, upTo: level, count: Self.itemCount)
            accessGranted = await service.requestAccess()
        }
        .onDisappear {
            service.cancel()
            SpeechService.shared.stop()
        }
    }

    // MARK: - Aktive Übung

    private func activeView(_ item: PronunciationTrainer.Item) -> some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    promptCard(item)
                    if let assessment {
                        resultCard(assessment, item: item)
                    }
                }
                .padding()
            }

            micControls(item)
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
        .task(id: item.id) {
            // Jede Aufgabe einmal vorsprechen.
            SpeechService.shared.speak(item.text, level: level, language: language)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                service.cancel()
                SpeechService.shared.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: items.isEmpty ? 0 : Double(index) / Double(items.count))
                .tint(Theme.accent)
            Text("\(index + 1)/\(items.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func promptCard(_ item: PronunciationTrainer.Item) -> some View {
        VStack(spacing: 12) {
            Text("Sprich nach:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(item.text)
                    .font(mode == .words ? .largeTitle.bold() : .title2.bold())
                    .multilineTextAlignment(.center)
                SpeakerButton(
                    speech: SpeechText(text: item.text, language: language),
                    level: level
                )
            }
            .frame(maxWidth: .infinity)

            Text(item.translation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Bewertung

    private func resultCard(_ assessment: PronunciationScorer.Assessment, item: PronunciationTrainer.Item) -> some View {
        let verdict = assessment.verdict
        let color: Color = switch verdict {
        case .excellent: Theme.success
        case .good: Theme.accent
        case .tryAgain: Theme.warning
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: verdict.symbol)
                    .font(.title2)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verdict.title)
                        .font(.headline)
                    Text("\(Int((assessment.score * 100).rounded())) % Übereinstimmung")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            FlowLayout(spacing: 6) {
                ForEach(assessment.words) { word in
                    Text(word.word)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            (word.matched ? Theme.success : Theme.danger).opacity(0.14),
                            in: Capsule()
                        )
                        .foregroundStyle(word.matched ? Theme.success : Theme.danger)
                }
            }

            if !assessment.transcript.isEmpty {
                Text("Verstanden: „\(assessment.transcript)“")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Nichts verstanden — sprich etwas lauter und deutlicher.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Aufnahme-Steuerung

    @ViewBuilder
    private func micControls(_ item: PronunciationTrainer.Item) -> some View {
        VStack(spacing: 10) {
            switch service.status {
            case .recording:
                Text("Aufnahme läuft — tippe zum Beenden")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !service.transcript.isEmpty {
                    Text(service.transcript)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            case .processing:
                Text("Wird ausgewertet …")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }

            HStack(spacing: 12) {
                micButton(item)

                if assessment != nil {
                    Button {
                        advance()
                    } label: {
                        Text(index + 1 == items.count ? "Fertig" : "Weiter")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func micButton(_ item: PronunciationTrainer.Item) -> some View {
        Button {
            toggleRecording(item)
        } label: {
            HStack(spacing: 10) {
                if service.status == .processing {
                    ProgressView()
                } else {
                    Image(systemName: service.status == .recording ? "stop.fill" : "mic.fill")
                        .symbolEffect(.pulse, isActive: service.status == .recording)
                }
                Text(micLabel)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(service.status == .recording ? Theme.danger : Theme.accent)
        .disabled(service.status == .processing || accessGranted != true)
    }

    private var micLabel: String {
        switch service.status {
        case .recording: return String(localized: "Stopp")
        case .processing: return String(localized: "Auswerten …")
        default: return assessment == nil
            ? String(localized: "Aufnehmen")
            : String(localized: "Nochmal versuchen")
        }
    }

    private func toggleRecording(_ item: PronunciationTrainer.Item) {
        switch service.status {
        case .recording:
            service.stopRecording { transcript in
                let result = PronunciationScorer.assess(target: item.text, transcript: transcript)
                assessment = result
                bestScores[item.id] = max(bestScores[item.id] ?? 0, result.score)
            }
        case .idle:
            SpeechService.shared.stop()
            assessment = nil
            service.startRecording(language: language, target: item.text)
        default:
            break
        }
    }

    private func advance() {
        service.cancel()
        SpeechService.shared.stop()
        assessment = nil
        withAnimation { index += 1 }
    }

    // MARK: - Berechtigungen / Verfügbarkeit

    private var deniedView: some View {
        infoScreen(
            symbol: "mic.slash.fill",
            title: String(localized: "Kein Mikrofon-Zugriff"),
            message: String(localized: "Für das Sprechtraining braucht die App Zugriff auf Mikrofon und Spracherkennung. Beides kannst du in den iOS-Einstellungen erlauben.")
        ) {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Einstellungen öffnen", destination: url)
                    .font(.headline)
            }
        }
    }

    private var unavailableView: some View {
        infoScreen(
            symbol: "waveform.slash",
            title: String(localized: "Spracherkennung nicht verfügbar"),
            message: String(localized: "Die Spracherkennung für \(content.direction.targetLanguageName) ist auf diesem Gerät gerade nicht verfügbar. Prüfe, ob Siri & Diktat aktiviert sind, und versuche es später erneut.")
        ) { EmptyView() }
    }

    private func infoScreen(
        symbol: String,
        title: String,
        message: String,
        @ViewBuilder action: () -> some View
    ) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(Theme.warning)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            action()
            Button("Schließen") { dismiss() }
                .padding(.top, 4)
            Spacer()
        }
    }

    // MARK: - Abschluss

    private var finishedView: some View {
        let passed = items.filter { (bestScores[$0.id] ?? 0) >= 0.6 }.count
        return VStack(spacing: 16) {
            Spacer()
            Image(systemName: items.isEmpty ? "moon.zzz.fill" : "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(items.isEmpty ? Theme.accent : Theme.success)
            Text(items.isEmpty ? "Noch kein Material" : "Sprechtraining beendet!")
                .font(.title2.bold())
            Text(items.isEmpty
                 ? "Für dieses Niveau gibt es noch keine Inhalte."
                 : "\(passed) von \(items.count) gut verständlich ausgesprochen — dranbleiben, dein Akzent wird immer besser.")
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
