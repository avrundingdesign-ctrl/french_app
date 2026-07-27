import Foundation

// MARK: - Identität

/// Feste IDs des KI-Partners. Er nutzt dieselben Typen wie ein echtes Tandem
/// (`CommunityProfile`, `ChatMessage`) — dadurch funktionieren Blasen-Layout,
/// Zeitstempel und Übersetzung ohne zweiten Datentyp.
enum AIPartnerIdentity {
    static let profileID = "ai_partner"
    static let matchID = "ai_local"
}

// MARK: - Persona

/// Der KI-Gesprächspartner: Muttersprachler der Lernsprache, der sich im
/// Niveau an die lernende Person anpasst.
///
/// Anders als im Tandem-Chat (dort schreibt jeder in *seiner* Lernsprache)
/// schreibt die KI durchgehend in der **Lernsprache des Nutzers** — sie übt
/// nichts, sie ist Muttersprachlerin. Das Verständnis sichert das Antippen
/// einer Nachricht ab (Übersetzung in die Muttersprache).
struct AIPersona: Equatable {
    /// Sprache, in der die KI schreibt — die Lernsprache des Nutzers.
    var language: TandemLanguage
    var level: CEFRLevel
    var name: String

    init(language: TandemLanguage, level: CEFRLevel) {
        self.language = language
        self.level = level
        // Bewusst andere Namen als die Demo-Tandempartner in
        // `MockCommunityService`, damit KI und Mensch nicht verwechselbar sind.
        self.name = language == .french ? "Manon" : "Jonas"
    }

    /// Muttersprache des Nutzers — Zielsprache beim Übersetzen.
    var viewerNativeLanguage: TandemLanguage { language.other }

    /// Überall sichtbare Kennzeichnung als KI (App-Review-Anforderung).
    var displayName: String { "\(name) (KI)" }

    /// Gesprächseinstiege für den leeren Chat — für A1 ist das leere
    /// Eingabefeld sonst die größte Hürde.
    var starters: [String] {
        switch (language, level) {
        case (.french, .a1), (.french, .a2):
            return ["Bonjour ! Je m'appelle…", "Comment ça va ?", "Tu habites où ?"]
        case (.french, _):
            return [
                "Raconte-moi ta journée.",
                "Qu'est-ce que tu aimes faire le week-end ?",
                "On parle de cuisine ?",
            ]
        case (.german, .a1), (.german, .a2):
            return ["Hallo! Ich heiße…", "Wie geht es dir?", "Wo wohnst du?"]
        case (.german, _):
            return [
                "Erzähl mir von deinem Tag.",
                "Was machst du gern am Wochenende?",
                "Reden wir übers Kochen?",
            ]
        }
    }

    private var levelHint: String {
        switch level {
        case .a1:
            return "Kurze Hauptsätze im Präsens, Alltagswortschatz, keine Nebensätze."
        case .a2:
            return "Einfache Sätze, Vergangenheit erlaubt, vertraute Alltagsthemen."
        case .b1:
            return "Auch Nebensätze und zusammenhängende Erzählungen."
        case .b2:
            return "Natürliches Tempo, auch abstrakte Themen und idiomatische Wendungen."
        case .c1:
            return "Wie mit einer muttersprachlichen Person, volle Bandbreite."
        }
    }

    /// Der System-Prompt entscheidet, ob sich das wie ein Gespräch anfühlt
    /// oder wie ein Chatbot. Die letzte Regel ist kein Stilwunsch: Ohne
    /// Thinking neigt das Modell dazu, Überlegungen in die sichtbare Antwort
    /// zu schreiben — die Anweisung fängt das ab.
    var systemPrompt: String {
        let target = language.label
        let native = viewerNativeLanguage.label
        return """
        Du bist \(name) und chattest mit einer Person, die \(target) auf Niveau \
        \(level.rawValue) lernt. \(target) ist deine Muttersprache.

        - Antworte AUSSCHLIESSLICH auf \(target). Nie auf \(native), auch nicht \
        in Klammern oder als Übersetzung.
        - Passe Wortschatz und Satzbau an Niveau \(level.rawValue) an. \(levelHint)
        - Halte das Gespräch am Laufen: ein bis drei Sätze antworten, dann eine \
        Rückfrage stellen.
        - Macht die Person einen Fehler, korrigiere ihn beiläufig, indem du den \
        Satz in deiner Antwort richtig wiederholst. Kein Grammatik-Vortrag, \
        keine Bewertung, kein Lob für Korrektheit.
        - Bleib in der Rolle. Keine Meta-Kommentare, kein Markdown, keine \
        Erklärung deiner Überlegungen. Gib nur die Chat-Antwort aus.
        """
    }
}

// MARK: - Fehler

/// Fehler werden früh in deutschen Klartext übersetzt — im Chat soll nie ein
/// roher HTTP-Code stehen.
enum AIPartnerError: LocalizedError, Equatable {
    case missingKey
    case invalidKey
    case rateLimited
    case overloaded
    case offline
    case refused
    case emptyResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Für den KI-Partner fehlt noch ein API-Key."
        case .invalidKey:
            return "Der API-Key wird nicht akzeptiert. Bitte prüf ihn noch einmal."
        case .rateLimited:
            return "Zu viele Anfragen kurz hintereinander. Warte einen Moment."
        case .overloaded:
            return "Der Dienst ist gerade überlastet. Versuch es gleich nochmal."
        case .offline:
            return "Keine Internetverbindung — der KI-Partner braucht eine."
        case .refused:
            return "Darauf antworte ich lieber nicht. Lass uns über etwas anderes reden."
        case .emptyResponse:
            return "Die Antwort kam leer zurück. Versuch es nochmal."
        case .server(let message):
            return message
        }
    }
}

// MARK: - Schnittstelle

protocol AIPartnerService: Sendable {
    /// Antwort auf den bisherigen Verlauf; die letzte Nachricht ist die des Nutzers.
    func reply(to history: [ChatMessage], as persona: AIPersona) async throws -> String

    /// Übersetzt einen Text — Rückfallebene, wenn Apple Translation auf dem
    /// Gerät nicht verfügbar ist (iOS 17, oder Sprachmodell nicht geladen).
    func translate(
        _ text: String,
        from source: TandemLanguage,
        to target: TandemLanguage
    ) async throws -> String
}

// MARK: - Anthropic Messages API

/// Anbindung an `POST https://api.anthropic.com/v1/messages`.
/// Für Swift gibt es kein offizielles Anthropic-SDK — daher direkt über
/// `URLSession`.
struct ClaudeAIPartnerService: AIPartnerService {
    /// A1/A2: günstig, und für Small Talk auf diesem Niveau völlig ausreichend.
    static let entryModel = "claude-haiku-4-5"
    /// Ab B1: Hier wird das beiläufige Korrigieren anspruchsvoll, und ein
    /// falsch „korrigierter" Satz schadet mehr als gar keine Korrektur —
    /// deshalb ist Sparen an dieser Stelle teurer als das Modell.
    static let advancedModel = "claude-opus-4-8"

    static func model(for level: CEFRLevel) -> String {
        level >= .b1 ? advancedModel : entryModel
    }

    /// `output_config.effort` gibt es erst ab der Opus-4.x-/Sonnet-5-Reihe.
    /// Haiku 4.5 beantwortet den Parameter mit 400, also darf er dort fehlen.
    static func supportsEffort(_ model: String) -> Bool {
        model != entryModel
    }
    /// Chat-Antworten sind ein bis drei Sätze; mehr Budget kostet nur.
    static let maxTokens = 512
    /// So viele Nachrichten gehen maximal als Verlauf mit. Die API ist
    /// zustandslos, der Verlauf also Teil jeder Anfrage — die Deckelung hält
    /// die Kosten pro Nachricht konstant statt stetig steigend.
    static let historyLimit = 20

    private let keyStore: AIKeyStoring
    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init(keyStore: AIKeyStoring = KeychainAIKeyStore(), session: URLSession = .shared) {
        self.keyStore = keyStore
        self.session = session
    }

    func reply(to history: [ChatMessage], as persona: AIPersona) async throws -> String {
        var turns = history.suffix(Self.historyLimit).map { message in
            Payload.Turn(
                role: message.senderProfileID == AIPartnerIdentity.profileID ? "assistant" : "user",
                content: message.text
            )
        }
        // Die API verlangt, dass der Verlauf mit einer Nutzer-Nachricht
        // beginnt — durch die Deckelung kann vorn eine KI-Antwort stehen.
        while turns.first?.role == "assistant" { turns.removeFirst() }
        guard !turns.isEmpty else { throw AIPartnerError.emptyResponse }

        return try await send(
            model: Self.model(for: persona.level),
            system: persona.systemPrompt,
            turns: turns
        )
    }

    func translate(
        _ text: String,
        from source: TandemLanguage,
        to target: TandemLanguage
    ) async throws -> String {
        let system = """
        Du bist ein Übersetzer. Übersetze den Text der nutzenden Person von \
        \(source.label) nach \(target.label).

        Gib ausschließlich die Übersetzung aus — keine Anführungszeichen, keine \
        Erklärung, keine Alternativen, kein Markdown. Behalte den Ton des \
        Originals bei; Umgangssprache bleibt Umgangssprache.
        """
        // Übersetzen ist die einfachere Aufgabe — dafür reicht immer das
        // günstige Modell, unabhängig vom Niveau.
        return try await send(
            model: Self.entryModel,
            system: system,
            turns: [Payload.Turn(role: "user", content: text)]
        )
    }

    // MARK: Transport

    private func send(model: String, system: String, turns: [Payload.Turn]) async throws -> String {
        guard let key = keyStore.load() else { throw AIPartnerError.missingKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60
        request.httpBody = try JSONEncoder().encode(
            Payload(
                model: model,
                maxTokens: Self.maxTokens,
                system: system,
                // Kurze Turns, Latenz zählt mehr als Tiefe. Haiku kennt `effort`
                // nicht und quittiert es mit 400 — dort bleibt das Feld weg.
                outputConfig: Self.supportsEffort(model) ? Payload.OutputConfig(effort: "low") : nil,
                messages: turns
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .cannotConnectToHost, .cannotFindHost, .timedOut:
                throw AIPartnerError.offline
            default:
                throw AIPartnerError.server(error.localizedDescription)
            }
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Self.error(for: status, body: data) }

        return try Self.text(fromBody: data)
    }

    /// Antwort auswerten. `stop_reason` zuerst prüfen: Bei `refusal` steht in
    /// `content` nichts Brauchbares.
    static func text(fromBody data: Data) throws -> String {
        let decoded: Reply
        do {
            decoded = try JSONDecoder().decode(Reply.self, from: data)
        } catch {
            throw AIPartnerError.server("Unerwartete Antwort vom Dienst.")
        }

        if decoded.stopReason == "refusal" { throw AIPartnerError.refused }

        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIPartnerError.emptyResponse }
        return text
    }

    static func error(for status: Int, body: Data) -> AIPartnerError {
        switch status {
        case 401, 403:
            return .invalidKey
        case 429:
            return .rateLimited
        case 500...599:
            // Schließt Anthropics 529 „overloaded" mit ein.
            return .overloaded
        default:
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: body) {
                return .server(envelope.error.message)
            }
            return .server("Unerwartete Antwort vom Dienst (HTTP \(status)).")
        }
    }

    // MARK: Wire-Format

    struct Payload: Encodable {
        let model: String
        let maxTokens: Int
        let system: String
        // Nur Modelle setzen, die `effort` kennen — Haiku 4.5 lehnt es mit 400 ab.
        let outputConfig: OutputConfig?
        let messages: [Turn]

        enum CodingKeys: String, CodingKey {
            case model, system, messages
            case maxTokens = "max_tokens"
            case outputConfig = "output_config"
        }

        struct OutputConfig: Encodable {
            let effort: String
        }

        struct Turn: Encodable, Equatable {
            let role: String
            let content: String
        }
    }

    struct Reply: Decodable {
        let content: [Block]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }

        struct Block: Decodable {
            let type: String
            let text: String?
        }
    }

    struct ErrorEnvelope: Decodable {
        let error: Detail

        struct Detail: Decodable {
            let type: String
            let message: String
        }
    }
}

// MARK: - Proxy-Zugang

/// Adresse des eigenen Proxys (CloudFlare Worker unter `server/`).
///
/// Der Anthropic-Key liegt **dort**, nicht in der App: Ein eingebauter Key
/// wäre aus dem App-Binary auslesbar und stünde außerdem im Klartext im
/// `x-api-key`-Header — jeder mit einem Debug-Proxy könnte auf fremde
/// Rechnung chatten.
struct AIProxyConfig: Sendable, Equatable {
    let baseURL: URL

    /// Aus der `Info.plist` (`AIProxyBaseURL`), damit die Adresse pro Build
    /// gesetzt werden kann, ohne Code zu ändern. Fehlt der Eintrag, gibt es
    /// schlicht keinen Proxy-Pfad.
    static func fromBundle(_ bundle: Bundle = .main) -> AIProxyConfig? {
        from(rawValue: bundle.object(forInfoDictionaryKey: "AIProxyBaseURL") as? String)
    }

    /// Ohne Bundle prüfbar. **Nur HTTPS** — der Nachweis über App Attest
    /// schützt nichts, wenn die Verbindung unverschlüsselt ist.
    static func from(rawValue: String?) -> AIProxyConfig? {
        guard
            let trimmed = rawValue?.trimmingCharacters(in: .whitespaces),
            !trimmed.isEmpty,
            let url = URL(string: trimmed),
            url.scheme == "https"
        else { return nil }
        return AIProxyConfig(baseURL: url)
    }
}

// MARK: - Dienstauswahl

/// Woher die Antworten kommen — steuert Hinweistext und Einrichtungs-Screen.
enum AIPartnerSource: Equatable {
    /// Apples On-Device-Modell: kostenlos, offline, ohne Einrichtung.
    case apple
    /// Eigener Anthropic-Key des Nutzers.
    case ownKey
    /// Über den eigenen Proxy — Premium, Key liegt serverseitig.
    case proxy
    case demo
    case unavailable(hint: String)

    var isUsable: Bool {
        if case .unavailable = self { return false }
        return true
    }

    /// Kurzer Hinweis unter dem Chat, damit erkennbar ist, was gerade läuft.
    var label: String {
        switch self {
        case .apple:  return "Apple Intelligence · auf dem Gerät, kostenlos"
        case .ownKey: return "Claude · über deinen eigenen API-Key"
        case .proxy:  return "Claude · über Premium"
        case .demo:   return "Demo-Modus · feste Antworten"
        case .unavailable: return ""
        }
    }
}

struct AIPartnerRouting {
    let source: AIPartnerSource
    let service: AIPartnerService?
}

/// Entscheidet, welcher Dienst den KI-Partner bedient.
///
/// Grundregel: **Apples Modell hat Vorrang**, weil es kostenlos, offline und
/// ohne jede Einrichtung läuft. Ausnahme ist B1/B2 — dort wird das beiläufige
/// Korrigieren anspruchsvoll, und ein kleines Modell, das einen richtigen Satz
/// „korrigiert", bringt der lernenden Person aktiv etwas Falsches bei.
enum AIPartnerResolver {
    static func resolve(
        isDemo: Bool,
        level: CEFRLevel,
        keyStore: AIKeyStoring,
        proxy: AIProxyConfig?,
        isPremium: Bool,
        appleAvailability: AppleAIPartnerService.Availability = AppleAIPartnerService.availability
    ) -> AIPartnerRouting {
        if isDemo {
            return AIPartnerRouting(source: .demo, service: MockAIPartnerService())
        }

        let claude: AIPartnerRouting? = {
            if keyStore.hasKey {
                return AIPartnerRouting(
                    source: .ownKey,
                    service: ClaudeAIPartnerService(keyStore: keyStore)
                )
            }
            if let proxy, isPremium {
                return AIPartnerRouting(
                    source: .proxy,
                    service: ProxyAIPartnerService(config: proxy)
                )
            }
            return nil
        }()

        if level >= .b1, let claude { return claude }
        if appleAvailability.isAvailable {
            return AIPartnerRouting(source: .apple, service: AppleAIPartnerService())
        }
        if let claude { return claude }

        return AIPartnerRouting(
            source: .unavailable(hint: hint(for: appleAvailability, hasProxy: proxy != nil)),
            service: nil
        )
    }

    /// Erklärt, was fehlt — und nennt zuerst den Weg, der nichts kostet.
    private static func hint(
        for availability: AppleAIPartnerService.Availability,
        hasProxy: Bool
    ) -> String {
        var lines = [availability.hint]
        if hasProxy {
            lines.append("Mit Premium schaltest du den KI-Partner auf jedem Gerät frei.")
        }
        lines.append("Alternativ kannst du unten einen eigenen Anthropic-API-Key hinterlegen.")
        return lines.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

// MARK: - Demo & Tests

/// Feste Antworten ohne Netz und ohne Key — damit der Flow im Demo-Modus
/// (`--community-demo`) und für App-Review-Screenshots vollständig
/// durchspielbar ist.
struct MockAIPartnerService: AIPartnerService {
    func reply(to history: [ChatMessage], as persona: AIPersona) async throws -> String {
        let replies = persona.language == .french
            ? [
                "Ah, intéressant ! Et toi, tu fais ça souvent ?",
                "Je vois ! Raconte-moi un peu plus.",
                "C'est chouette. Qu'est-ce que tu aimes le plus ?",
                "D'accord ! Et le week-end, tu fais quoi ?",
            ]
            : [
                "Ach, interessant! Und machst du das oft?",
                "Verstehe! Erzähl mir ein bisschen mehr.",
                "Das ist schön. Was magst du am liebsten?",
                "Alles klar! Und am Wochenende, was machst du da?",
            ]
        // Bewusst zustandslos (aus dem Verlauf abgeleitet): Die View darf den
        // Service jederzeit neu erzeugen, ohne dass die Rotation zurückspringt.
        return replies[history.count % replies.count]
    }

    func translate(
        _ text: String,
        from source: TandemLanguage,
        to target: TandemLanguage
    ) async throws -> String {
        "(Demo-Übersetzung) \(text)"
    }
}
