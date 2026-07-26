import XCTest
@testable import FrenchApp

/// KI-Gesprächspartner: Persona/Prompt, Wire-Format der Anthropic-API und
/// Fehlerübersetzung. Läuft komplett ohne Netz — Anfragen gehen gegen einen
/// `URLProtocol`-Stub, damit auch der gebaute Request prüfbar ist.
final class AIPartnerTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeService(
        key: String? = "sk-ant-test",
        status: Int = 200,
        body: Data = AIPartnerTests.replyJSON("Salut !")
    ) -> ClaudeAIPartnerService {
        StubURLProtocol.respond(status: status, body: body)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return ClaudeAIPartnerService(
            keyStore: InMemoryAIKeyStore(key: key),
            session: URLSession(configuration: config)
        )
    }

    private static func replyJSON(_ text: String, stopReason: String = "end_turn") -> Data {
        Data("""
        {"content":[{"type":"text","text":"\(text)"}],"stop_reason":"\(stopReason)"}
        """.utf8)
    }

    // MARK: - Persona & Prompt

    func testPersonaWritesInLearningLanguageNotNativeLanguage() {
        // Deutscher Lerner: Die KI schreibt Französisch, übersetzt wird nach Deutsch.
        let persona = AIPersona(language: .french, level: .a1)
        XCTAssertEqual(persona.language, .french)
        XCTAssertEqual(persona.viewerNativeLanguage, .german)
        XCTAssertTrue(persona.displayName.contains("(KI)"), "KI muss überall gekennzeichnet sein")
    }

    func testSystemPromptCarriesLanguageAndLevel() {
        let prompt = AIPersona(language: .french, level: .b1).systemPrompt
        XCTAssertTrue(prompt.contains("Französisch"))
        XCTAssertTrue(prompt.contains("B1"))
        XCTAssertTrue(prompt.contains("AUSSCHLIESSLICH"), "Sprachbindung muss im Prompt stehen")
        XCTAssertTrue(
            prompt.contains("Gib nur die Chat-Antwort aus"),
            "Ohne Thinking sonst Gefahr, dass Überlegungen in der Antwort landen"
        )
    }

    func testLevelChangesPromptGuidance() {
        let a1 = AIPersona(language: .french, level: .a1).systemPrompt
        let b2 = AIPersona(language: .french, level: .b2).systemPrompt
        XCTAssertNotEqual(a1, b2)
        XCTAssertTrue(a1.contains("Präsens"))
        XCTAssertTrue(b2.contains("idiomatische"))
    }

    func testStartersExistForEveryLevel() {
        for language in TandemLanguage.allCases {
            for level in CEFRLevel.allCases {
                let starters = AIPersona(language: language, level: level).starters
                XCTAssertFalse(starters.isEmpty, "\(language.label)/\(level.rawValue) ohne Einstiege")
            }
        }
    }

    // MARK: - Antwort auswerten

    func testMultipleTextBlocksAreJoined() throws {
        let body = Data("""
        {"content":[{"type":"text","text":"Salut ! "},{"type":"text","text":"Ça va ?"}],
         "stop_reason":"end_turn"}
        """.utf8)
        XCTAssertEqual(try ClaudeAIPartnerService.text(fromBody: body), "Salut ! Ça va ?")
    }

    func testNonTextBlocksAreIgnored() throws {
        let body = Data("""
        {"content":[{"type":"thinking"},{"type":"text","text":"Bonjour"}],
         "stop_reason":"end_turn"}
        """.utf8)
        XCTAssertEqual(try ClaudeAIPartnerService.text(fromBody: body), "Bonjour")
    }

    func testRefusalBecomesFriendlyError() {
        let body = Self.replyJSON("", stopReason: "refusal")
        XCTAssertThrowsError(try ClaudeAIPartnerService.text(fromBody: body)) { error in
            XCTAssertEqual(error as? AIPartnerError, .refused)
        }
    }

    func testEmptyAnswerIsAnError() {
        XCTAssertThrowsError(try ClaudeAIPartnerService.text(fromBody: Self.replyJSON("   "))) { error in
            XCTAssertEqual(error as? AIPartnerError, .emptyResponse)
        }
    }

    // MARK: - Fehlerübersetzung

    func testHTTPStatusMapsToGermanMessages() {
        let empty = Data()
        XCTAssertEqual(ClaudeAIPartnerService.error(for: 401, body: empty), .invalidKey)
        XCTAssertEqual(ClaudeAIPartnerService.error(for: 403, body: empty), .invalidKey)
        XCTAssertEqual(ClaudeAIPartnerService.error(for: 429, body: empty), .rateLimited)
        XCTAssertEqual(ClaudeAIPartnerService.error(for: 500, body: empty), .overloaded)
        XCTAssertEqual(ClaudeAIPartnerService.error(for: 529, body: empty), .overloaded)
    }

    func testServerErrorMessageIsPassedThrough() {
        let body = Data("""
        {"type":"error","error":{"type":"invalid_request_error","message":"max_tokens zu groß"}}
        """.utf8)
        XCTAssertEqual(ClaudeAIPartnerService.error(for: 400, body: body), .server("max_tokens zu groß"))
    }

    func testEveryErrorHasReadableText() {
        let cases: [AIPartnerError] = [
            .missingKey, .invalidKey, .rateLimited, .overloaded,
            .offline, .refused, .emptyResponse, .server("Test"),
        ]
        for error in cases {
            let text = error.errorDescription ?? ""
            XCTAssertFalse(text.isEmpty, "\(error) ohne Meldung")
            XCTAssertFalse(text.contains("HTTP 0"), "Rohe Codes gehören nicht in den Chat")
        }
    }

    // MARK: - Request-Bau

    func testMissingKeyFailsBeforeAnyRequest() async {
        let service = makeService(key: nil)
        do {
            _ = try await service.reply(to: [message("Bonjour", from: "me")], as: persona)
            XCTFail("Ohne Key darf keine Anfrage rausgehen")
        } catch {
            XCTAssertEqual(error as? AIPartnerError, .missingKey)
            XCTAssertNil(StubURLProtocol.lastRequestBody, "Es wurde trotzdem gesendet")
        }
    }

    func testRequestCarriesModelAndSystemPrompt() async throws {
        let service = makeService()
        _ = try await service.reply(to: [message("Bonjour", from: "me")], as: persona)

        let payload = try XCTUnwrap(StubURLProtocol.lastRequestJSON())
        XCTAssertEqual(payload["model"] as? String, ClaudeAIPartnerService.model)
        XCTAssertEqual(payload["max_tokens"] as? Int, ClaudeAIPartnerService.maxTokens)
        let system = try XCTUnwrap(payload["system"] as? String)
        XCTAssertTrue(system.contains("Französisch"))
        let outputConfig = try XCTUnwrap(payload["output_config"] as? [String: Any])
        XCTAssertEqual(outputConfig["effort"] as? String, "low")
    }

    func testHistoryIsCappedAtLimit() async throws {
        let service = makeService()
        let history = (0..<50).map { index in
            message("Nachricht \(index)", from: index.isMultiple(of: 2) ? "me" : AIPartnerIdentity.profileID)
        }
        _ = try await service.reply(to: history, as: persona)

        let payload = try XCTUnwrap(StubURLProtocol.lastRequestJSON())
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertLessThanOrEqual(
            messages.count, ClaudeAIPartnerService.historyLimit,
            "Verlauf muss gedeckelt sein, sonst steigen die Kosten pro Nachricht endlos"
        )
        XCTAssertEqual(messages.first?["role"] as? String, "user", "API verlangt Start mit user")
    }

    func testLeadingAssistantTurnsAreDropped() async throws {
        let service = makeService()
        let history = [
            message("Salut !", from: AIPartnerIdentity.profileID),
            message("Bonjour", from: "me"),
        ]
        _ = try await service.reply(to: history, as: persona)

        let payload = try XCTUnwrap(StubURLProtocol.lastRequestJSON())
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
    }

    func testSenderMapsToCorrectRole() async throws {
        let service = makeService()
        let history = [
            message("Bonjour", from: "me"),
            message("Salut !", from: AIPartnerIdentity.profileID),
            message("Ça va", from: "me"),
        ]
        _ = try await service.reply(to: history, as: persona)

        let payload = try XCTUnwrap(StubURLProtocol.lastRequestJSON())
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"])
    }

    // MARK: - Übersetzung

    func testTranslateSendsOnlyTheText() async throws {
        let service = makeService(body: Self.replyJSON("Guten Tag"))
        let result = try await service.translate("Bonjour", from: .french, to: .german)
        XCTAssertEqual(result, "Guten Tag")

        let payload = try XCTUnwrap(StubURLProtocol.lastRequestJSON())
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["content"] as? String, "Bonjour")
        let system = try XCTUnwrap(payload["system"] as? String)
        XCTAssertTrue(system.contains("Französisch") && system.contains("Deutsch"))
    }

    // MARK: - Schlüsselablage

    func testInMemoryKeyStoreRoundTrip() {
        let store = InMemoryAIKeyStore()
        XCTAssertFalse(store.hasKey)
        store.save("  sk-ant-123  ")
        XCTAssertEqual(store.load(), "sk-ant-123", "Whitespace wird getrimmt")
        XCTAssertTrue(store.hasKey)
        store.save("")
        XCTAssertNil(store.load(), "Leerer Key löscht")
        store.save("sk-ant-456")
        store.clear()
        XCTAssertNil(store.load())
    }

    // MARK: - Verlauf

    func testChatStoreRoundTripAndReset() async {
        let filename = "ai-chat-test-\(UUID().uuidString).json"
        let store = AIChatStore(filename: filename)
        defer { Self.removeStoreFile(filename) }

        var loaded = await store.load()
        XCTAssertTrue(loaded.isEmpty)

        await store.append(message("Bonjour", from: "me"))
        await store.append(message("Salut !", from: AIPartnerIdentity.profileID))

        // Frische Instanz: Der Verlauf muss von der Platte kommen.
        loaded = await AIChatStore(filename: filename).load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.first?.text, "Bonjour")
        XCTAssertEqual(loaded.last?.senderProfileID, AIPartnerIdentity.profileID)

        await store.reset()
        XCTAssertTrue(await AIChatStore(filename: filename).load().isEmpty)
    }

    func testChatStoreCapsStoredMessages() async {
        let filename = "ai-chat-cap-\(UUID().uuidString).json"
        let store = AIChatStore(filename: filename)
        defer { Self.removeStoreFile(filename) }

        for index in 0..<(AIChatStore.storageLimit + 20) {
            await store.append(message("Nachricht \(index)", from: "me"))
        }

        let loaded = await store.load()
        XCTAssertEqual(loaded.count, AIChatStore.storageLimit, "Datei darf nicht endlos wachsen")
        XCTAssertEqual(loaded.last?.text, "Nachricht \(AIChatStore.storageLimit + 19)")
    }

    private static func removeStoreFile(_ filename: String) {
        let manager = FileManager.default
        guard let directory = try? manager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) else { return }
        try? manager.removeItem(at: directory.appendingPathComponent(filename))
    }

    // MARK: - Hilfen

    private var persona: AIPersona { AIPersona(language: .french, level: .a1) }

    private func message(_ text: String, from senderID: String) -> ChatMessage {
        ChatMessage(
            id: UUID().uuidString,
            matchID: AIPartnerIdentity.matchID,
            senderProfileID: senderID,
            text: text,
            language: .french,
            sentAt: .now
        )
    }
}

// MARK: - URLProtocol-Stub

/// Fängt Anfragen ab, liefert eine feste Antwort und merkt sich den Body —
/// so ist auch der *gebaute* Request prüfbar, nicht nur die Auswertung.
final class StubURLProtocol: URLProtocol {
    static var responseStatus = 200
    static var responseBody = Data()
    static var lastRequestBody: Data?

    static func respond(status: Int, body: Data) {
        responseStatus = status
        responseBody = body
        lastRequestBody = nil
    }

    static func reset() {
        responseStatus = 200
        responseBody = Data()
        lastRequestBody = nil
    }

    static func lastRequestJSON() -> [String: Any]? {
        guard let body = lastRequestBody else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession verschiebt den Body in einen Stream — httpBody ist hier nil.
        Self.lastRequestBody = request.httpBody ?? request.httpBodyStream.map(Self.drain)

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.responseStatus,
            httpVersion: "HTTP/1.1",
            headerFields: ["content-type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
