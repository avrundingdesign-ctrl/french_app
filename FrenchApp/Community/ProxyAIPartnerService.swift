import Foundation

/// KI-Partner über den eigenen Proxy (CloudFlare Worker unter `server/`).
///
/// Die App schickt nur Modus, Sprache, Niveau und die Nachrichten — **den
/// System-Prompt baut der Worker selbst**. Das ist Absicht: Wer die Adresse aus
/// dem Binary liest, kann den Proxy dann nicht als kostenlosen Allzweck-Claude
/// missbrauchen, sondern nur als Sprachlern-Partner.
///
/// - Important: Der Prompt im Worker (`buildSystemPrompt` in
///   `server/src/prompt.ts`) und `AIPersona.systemPrompt` beschreiben dieselbe
///   Rolle. Ändert sich einer, muss der andere mitziehen.
struct ProxyAIPartnerService: AIPartnerService {
    let config: AIProxyConfig
    private let session: URLSession
    private let attest: AppAttestClient

    init(config: AIProxyConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        self.attest = AppAttestClient(baseURL: config.baseURL, session: session)
    }

    // MARK: - AIPartnerService

    func reply(to history: [ChatMessage], as persona: AIPersona) async throws -> String {
        var turns = history.suffix(ClaudeAIPartnerService.historyLimit).map { message in
            Turn(
                role: message.senderProfileID == AIPartnerIdentity.profileID ? "assistant" : "user",
                content: message.text
            )
        }
        while turns.first?.role == "assistant" { turns.removeFirst() }
        guard !turns.isEmpty else { throw AIPartnerError.emptyResponse }

        return try await post(ChatRequest(
            mode: "chat",
            language: persona.language.rawValue,
            level: persona.level.rawValue,
            name: persona.name,
            messages: turns,
            nonce: UUID().uuidString
        ))
    }

    func translate(
        _ text: String,
        from source: TandemLanguage,
        to target: TandemLanguage
    ) async throws -> String {
        try await post(TranslateRequest(
            mode: "translate",
            sourceLanguage: source.rawValue,
            targetLanguage: target.rawValue,
            text: text,
            nonce: UUID().uuidString
        ))
    }

    // MARK: - Transport

    private func post<Body: Encodable>(_ body: Body) async throws -> String {
        // Genau diese Bytes werden signiert **und** gesendet — der Server
        // prüft den Hash gegen den empfangenen Body.
        let payload = try JSONEncoder().encode(body)

        let headers: [String: String]
        do {
            headers = try await attest.headers(for: payload)
        } catch let error as AppAttestClient.AttestError {
            throw AIPartnerError.server(error.localizedDescription)
        }

        var request = URLRequest(url: config.baseURL.appendingPathComponent("v1/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        request.timeoutInterval = 60
        request.httpBody = payload

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
        guard status == 200 else {
            throw try await mapped(status: status, body: data)
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = (json["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            throw AIPartnerError.emptyResponse
        }
        return text
    }

    private func mapped(status: Int, body: Data) async throws -> AIPartnerError {
        let error = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])
            .flatMap { $0?["error"] as? [String: Any] }
        let code = error?["code"] as? String
        let message = error?["message"] as? String

        switch code {
        case "attest_failed", "unknown_key":
            // Server kennt unseren Schlüssel nicht mehr → beim nächsten Mal
            // neu anmelden.
            await attest.resetRegistration()
            return .server("Die gesicherte Verbindung musste neu aufgebaut werden. Versuch es nochmal.")
        case "rate_limited":
            return .rateLimited
        case "refused":
            return .refused
        case "not_entitled":
            return .server(message ?? "Für den KI-Partner brauchst du Premium.")
        default:
            switch status {
            case 401, 403: return .server(message ?? "Der Server hat die Anfrage abgelehnt.")
            case 429: return .rateLimited
            case 500...599: return .overloaded
            default: return .server(message ?? "Unerwartete Antwort vom Server (HTTP \(status)).")
            }
        }
    }

    // MARK: - Wire-Format

    private struct Turn: Encodable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Encodable {
        let mode: String
        let language: String
        let level: String
        let name: String
        let messages: [Turn]
        let nonce: String
    }

    private struct TranslateRequest: Encodable {
        let mode: String
        let sourceLanguage: String
        let targetLanguage: String
        let text: String
        let nonce: String
    }
}
