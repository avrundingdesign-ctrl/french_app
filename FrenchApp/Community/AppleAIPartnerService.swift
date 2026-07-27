import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// KI-Partner über Apples On-Device-Modell (Foundation Models, ab iOS 26).
///
/// Kostenlos, offline, privat — nichts verlässt das Gerät, kein API-Key, keine
/// Einrichtung. Deshalb hat dieser Dienst Vorrang vor Claude.
///
/// Das Modell ist mit rund 3 Mrd. Parametern deutlich kleiner als Claude. Für
/// Small Talk auf A1/A2 reicht das gut; beim beiläufigen Korrigieren auf B1/B2
/// ist es schwächer — deshalb sagt `AIPartnerResolver` ab B1 lieber Claude,
/// wenn beides verfügbar ist.
///
/// - Note: `#if canImport(FoundationModels)` hält die Datei mit älteren Xcode-
///   Versionen übersetzbar (Deployment-Target der App ist iOS 17). Ohne das
///   SDK meldet der Dienst schlicht „nicht verfügbar".
struct AppleAIPartnerService: AIPartnerService {

    /// Warum Apples Modell (nicht) nutzbar ist — bestimmt den Hinweistext.
    enum Availability: Equatable {
        case available
        /// Gerät kann Apple Intelligence grundsätzlich nicht.
        case deviceNotEligible
        /// Gerät könnte, Apple Intelligence ist aber ausgeschaltet.
        case notEnabled
        /// Modell wird gerade noch geladen.
        case modelNotReady
        /// iOS zu alt oder ohne Foundation-Models-SDK gebaut.
        case needsNewerOS

        var isAvailable: Bool { self == .available }

        /// Nur `.notEnabled` kann der Nutzer selbst beheben.
        var hint: String {
            switch self {
            case .available:
                return ""
            case .deviceNotEligible:
                return "Dieses iPhone unterstützt Apple Intelligence nicht."
            case .notEnabled:
                return "Schalte Apple Intelligence in den Einstellungen ein, dann ist der KI-Partner sofort nutzbar — kostenlos und ohne Konto."
            case .modelNotReady:
                return "Apple Intelligence lädt gerade noch. Versuch es in ein paar Minuten nochmal."
            case .needsNewerOS:
                return "Der kostenlose KI-Partner von Apple braucht iOS 26 oder neuer."
            }
        }
    }

    /// Ist Apples Modell auf diesem Gerät gerade einsatzbereit?
    ///
    /// - Important: Die Fallunterscheidung unten ist der einzige Ort, der die
    ///   Foundation-Models-API im Detail anfasst. Sollten sich Namen im SDK
    ///   unterscheiden, ist nur diese Funktion anzupassen.
    static var availability: Availability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return .deviceNotEligible
                case .appleIntelligenceNotEnabled: return .notEnabled
                case .modelNotReady: return .modelNotReady
                @unknown default: return .deviceNotEligible
                }
            @unknown default:
                return .deviceNotEligible
            }
        }
        #endif
        return .needsNewerOS
    }

    static var isAvailable: Bool { availability.isAvailable }

    // MARK: - AIPartnerService

    func reply(to history: [ChatMessage], as persona: AIPersona) async throws -> String {
        try await generate(
            instructions: persona.systemPrompt,
            prompt: Self.conversationPrompt(history: history, persona: persona)
        )
    }

    func translate(
        _ text: String,
        from source: TandemLanguage,
        to target: TandemLanguage
    ) async throws -> String {
        try await generate(
            instructions: """
            Du bist ein Übersetzer. Übersetze von \(source.label) nach \
            \(target.label). Gib ausschließlich die Übersetzung aus — keine \
            Anführungszeichen, keine Erklärung, keine Alternativen.
            """,
            prompt: text
        )
    }

    // MARK: - Prompt

    /// Apples Sessions sind zwar zustandsbehaftet, aber unser Protokoll reicht
    /// den Verlauf ohnehin bei jedem Zug mit. Wir bauen deshalb pro Antwort
    /// eine frische Session und legen den Verlauf in den Prompt — das ist
    /// robust gegenüber App-Neustarts und braucht keine Session-Verwaltung.
    static func conversationPrompt(history: [ChatMessage], persona: AIPersona) -> String {
        let recent = history.suffix(historyLimit)
        guard !recent.isEmpty else {
            return "Begrüße die lernende Person und stell eine einfache Frage."
        }

        let transcript = recent.map { message in
            let speaker = message.senderProfileID == AIPartnerIdentity.profileID
                ? persona.name
                : "Lernende Person"
            return "\(speaker): \(message.text)"
        }.joined(separator: "\n")

        return """
        Bisheriges Gespräch:
        \(transcript)

        Antworte jetzt als \(persona.name) auf die letzte Nachricht der \
        lernenden Person. Gib nur deine Antwort aus, ohne Namensvorspann.
        """
    }

    /// Kleiner als bei Claude: Das On-Device-Modell hat ein knapperes
    /// Kontextfenster, und ein überlanger Prompt kostet hier Rechenzeit
    /// auf dem Gerät statt Geld.
    static let historyLimit = 12

    // MARK: - Ausführung

    private func generate(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard Self.isAvailable else {
                throw AIPartnerError.server(Self.availability.hint)
            }
            let session = LanguageModelSession(instructions: instructions)
            do {
                let response = try await session.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw AIPartnerError.emptyResponse }
                return text
            } catch let error as AIPartnerError {
                throw error
            } catch let error as LanguageModelSession.GenerationError {
                throw Self.mapped(error)
            }
        }
        #endif
        throw AIPartnerError.server(Self.availability.hint)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func mapped(_ error: LanguageModelSession.GenerationError) -> AIPartnerError {
        switch error {
        case .guardrailViolation:
            return .refused
        case .exceededContextWindowSize:
            return .server("Das Gespräch ist zu lang geworden — starte es über das Menü neu.")
        default:
            return .server("Apple Intelligence konnte gerade nicht antworten. Versuch es nochmal.")
        }
    }
    #endif
}
