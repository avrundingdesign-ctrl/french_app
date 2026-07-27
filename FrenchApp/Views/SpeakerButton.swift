import SwiftUI

/// Lautsprecher-Button: liest einen Text in der Lernsprache vor.
/// Überall dort, wo Wörter oder Sätze der Lernsprache stehen — Übungen,
/// Vokabelkarten, Feedback — damit man sich die Aussprache anhören kann.
struct SpeakerButton: View {
    let speech: SpeechText
    /// Bestimmt das Sprechtempo (A1/A2 langsamer).
    var level: CEFRLevel = .a2
    var font: Font = .title3

    @State private var isPlaying = false

    var body: some View {
        Button(action: play) {
            Image(systemName: isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                .font(font)
                .foregroundStyle(Theme.accent)
                .symbolEffect(.pulse, isActive: isPlaying)
                .frame(minWidth: 30, minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Vorlesen")
        .onDisappear {
            if isPlaying { SpeechService.shared.stop() }
        }
    }

    private func play() {
        guard !isPlaying else {
            SpeechService.shared.stop()
            return
        }
        isPlaying = true
        SpeechService.shared.speak(speech, level: level) {
            isPlaying = false
        }
    }
}
