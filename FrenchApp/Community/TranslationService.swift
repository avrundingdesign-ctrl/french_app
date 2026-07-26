import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Eine offene Übersetzungsanfrage: Text mit stabiler ID (= Nachrichten-ID).
struct TranslationRequest: Equatable, Identifiable {
    let id: String
    let text: String
}

/// Übersetzt on-device in ein festes Sprachpaar (Apple-Translation-Framework,
/// ab iOS 18 — offline, kostenlos, privat).
///
/// Unsichtbare Hilfs-View: beobachtet die offenen Anfragen und füllt das
/// Übersetzungs-Cache-Binding. **Pro Sprachpaar eine Instanz** —
/// `TranslationSession.Configuration` bindet eine Session an genau ein Paar,
/// und ein Chat braucht beide Richtungen (Partner-Nachrichten hinein, eigene
/// Nachrichten hinaus).
struct TranslationBridge: View {
    let requests: [TranslationRequest]
    let source: TandemLanguage
    let target: TandemLanguage
    @Binding var translations: [String: String]
    /// Gerufen, wenn on-device nicht übersetzt werden kann (iOS 17, oder
    /// Sprachmodell nicht geladen) — der Aufrufer kann dann auf die KI
    /// ausweichen, statt den Nutzer im Leeren stehen zu lassen.
    var onUnavailable: ([TranslationRequest]) -> Void = { _ in }

    var body: some View {
        if #available(iOS 18.0, *) {
            TranslationRunner(
                requests: requests,
                source: source,
                target: target,
                translations: $translations,
                onUnavailable: onUnavailable
            )
        } else {
            // iOS 17: gar keine On-Device-Übersetzung — direkt weiterreichen.
            Color.clear
                .frame(width: 0, height: 0)
                .task(id: requests.map(\.id).joined(separator: "|")) {
                    let open = requests.filter { translations[$0.id] == nil }
                    guard !open.isEmpty else { return }
                    onUnavailable(open)
                }
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
    let requests: [TranslationRequest]
    let source: TandemLanguage
    let target: TandemLanguage
    @Binding var translations: [String: String]
    let onUnavailable: ([TranslationRequest]) -> Void

    @State private var configuration: TranslationSession.Configuration?

    private var pending: [TranslationRequest] {
        requests.filter { translations[$0.id] == nil }
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: pending.map(\.id).joined(separator: "|")) {
                guard !pending.isEmpty else { return }
                if configuration == nil {
                    configuration = TranslationSession.Configuration(
                        source: Locale.Language(identifier: source.rawValue),
                        target: Locale.Language(identifier: target.rawValue)
                    )
                } else {
                    // Neue Anfragen: bestehende Session erneut anstoßen.
                    configuration?.invalidate()
                }
            }
            .translationTask(configuration) { session in
                let open = pending
                do {
                    for request in open {
                        let response = try await session.translate(request.text)
                        translations[request.id] = response.targetText
                    }
                } catch {
                    // Modell (noch) nicht verfügbar → Aufrufer entscheidet.
                    onUnavailable(open)
                }
            }
    }
}

/// Automatische Übersetzung der Partner-Nachrichten im Tandem-Chat in die
/// Lernsprache des Betrachters — das bestehende Immersions-Verhalten, jetzt
/// auf `TranslationBridge` aufgesetzt.
struct ChatTranslationBridge: View {
    let messages: [ChatMessage]
    let viewer: CommunityProfile
    @Binding var translations: [String: String]
    var onUnavailable: ([TranslationRequest]) -> Void = { _ in }

    var body: some View {
        let direction = ChatDisplay.translationDirection(for: viewer)
        TranslationBridge(
            requests: messages
                .filter { ChatDisplay.needsTranslation($0, for: viewer) }
                .map { TranslationRequest(id: $0.id, text: $0.text) },
            source: direction.source,
            target: direction.target,
            translations: $translations,
            onUnavailable: onUnavailable
        )
    }

    static var isSupported: Bool { TranslationBridge.isSupported }
}
