import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Übersetzt Partner-Nachrichten on-device in die Lernsprache des Betrachters
/// (Apple-Translation-Framework, ab iOS 18 — offline, kostenlos, privat).
///
/// Unsichtbare Hilfs-View: beobachtet die Nachrichtenliste und füllt das
/// Übersetzungs-Cache-Binding. Auf iOS 17 bleibt der Originaltext stehen.
struct ChatTranslationBridge: View {
    let messages: [ChatMessage]
    let viewer: CommunityProfile
    @Binding var translations: [String: String]

    var body: some View {
        if #available(iOS 18.0, *) {
            TranslationRunner(messages: messages, viewer: viewer, translations: $translations)
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    /// Gibt es auf diesem System überhaupt On-Device-Übersetzung?
    static var isSupported: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }
}

@available(iOS 18.0, *)
private struct TranslationRunner: View {
    let messages: [ChatMessage]
    let viewer: CommunityProfile
    @Binding var translations: [String: String]

    @State private var configuration: TranslationSession.Configuration?

    private var pending: [ChatMessage] {
        messages.filter {
            ChatDisplay.needsTranslation($0, for: viewer) && translations[$0.id] == nil
        }
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: pending.map(\.id).joined(separator: "|")) {
                guard !pending.isEmpty else { return }
                if configuration == nil {
                    let direction = ChatDisplay.translationDirection(for: viewer)
                    configuration = TranslationSession.Configuration(
                        source: Locale.Language(identifier: direction.source.rawValue),
                        target: Locale.Language(identifier: direction.target.rawValue)
                    )
                } else {
                    // Neue Nachrichten: bestehende Session erneut anstoßen.
                    configuration?.invalidate()
                }
            }
            .translationTask(configuration) { session in
                for message in pending {
                    do {
                        let response = try await session.translate(message.text)
                        translations[message.id] = response.targetText
                    } catch {
                        // Modell (noch) nicht verfügbar → Original bleibt sichtbar.
                        break
                    }
                }
            }
    }
}
