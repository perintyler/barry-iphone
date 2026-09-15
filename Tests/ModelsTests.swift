import XCTest
@testable import Barry

/// Decoding tests pinned to REAL payload shapes captured from the live API
/// (see fixtures/ for provenance). If these fail after an API change, the
/// contract moved — update the models AND the fixtures together.
final class ModelsTests: XCTestCase {

    func testDecodesSessionListPayload() throws {
        let json = """
        {"sessions":[{"id":"jab7rOGdqVJsQOYhWwAz7","name":"jab7rOGd","systemPrompt":null,
        "summary":"### 2026-09-11","repoPath":"/Users/tyler/repos/barry","identityId":3,
        "identitySource":null,"status":"running","traits":[],"scope":null,"pinned":false,
        "useWorktree":false,"worktreeStatus":null,"worktreePath":null,"baseRepoPath":null,
        "source":"cli","provider":"claude","model":"claude-opus-5","messageCount":14,
        "lastMessageAt":"2026-09-11T06:52:44.284Z",
        "statusUpdate":{"summary":"building the app","phase":"building","updatedAt":"2026-09-11T06:52:00.000Z"},
        "createdAt":"2026-09-11T06:36:25.132Z","startedAt":null}],"nextCursor":null}
        """
        let page = try JSONDecoder().decode(SessionsPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.sessions.count, 1)
        let s = page.sessions[0]
        XCTAssertEqual(s.id, "jab7rOGdqVJsQOYhWwAz7")
        XCTAssertEqual(s.repoName, "barry")
        XCTAssertTrue(s.isRunning)
        XCTAssertEqual(s.statusUpdate?.phase, "building")
        XCTAssertEqual(s.messageCount, 14)
    }

    func testDecodesTextAndToolMessages() throws {
        let json = """
        {"messages":[
          {"type":"text","sessionId":"abc","content":"hello","role":"user","sequence":0,
           "createdAt":"2026-09-11T06:37:55.059Z"},
          {"type":"text","sessionId":"abc","content":"hi back","role":"assistant","sequence":1,
           "createdAt":"2026-09-11T06:38:00.000Z"},
          {"type":"tool_start","sessionId":"abc","name":"mcp__git__status","input":{"cwd":"/tmp"},
           "result":null,"hasDetail":true,"toolUseId":"toolu_1","sequence":2,
           "createdAt":"2026-09-11T06:38:01.000Z"},
          {"type":"tool_start","sessionId":"abc","name":"Bash",
           "input":"{\\"command\\":\\"ls -la\\"}","result":null,"hasDetail":true,
           "toolUseId":"toolu_2","sequence":3,"createdAt":"2026-09-11T06:38:02.000Z"}
        ],"nextSequence":3,"hasMore":false}
        """
        let page = try JSONDecoder().decode(MessagesPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.messages.count, 4)
        XCTAssertTrue(page.messages[0].isUser)
        XCTAssertTrue(page.messages[1].isAssistant)
        XCTAssertTrue(page.messages[2].isTool)
        // Object input re-serializes for display
        XCTAssertTrue(page.messages[2].input!.text.contains("cwd"))
        // String input (summary mode) passes through verbatim
        XCTAssertEqual(page.messages[3].input?.text, "{\"command\":\"ls -la\"}")
        XCTAssertEqual(page.messages[2].toolLabel, "git status")
        XCTAssertEqual(page.messages[3].toolLabel, "Bash")
    }

    /// Regression: a tool whose OWN name contains underscores
    /// ("set_current_session_name") must not get word-mangled by splitting
    /// on every underscore — only the "__" namespace delimiter is a split point.
    func testToolLabelPreservesUnderscoredToolNames() throws {
        let json = """
        {"messages":[
          {"type":"tool_start","sessionId":"abc","name":"mcp__session__set_current_session_name",
           "input":null,"result":null,"hasDetail":true,"toolUseId":"t1","sequence":0,
           "createdAt":"2026-09-11T00:00:00.000Z"}
        ],"nextSequence":0,"hasMore":false}
        """
        let page = try JSONDecoder().decode(MessagesPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.messages[0].toolLabel, "session set_current_session_name")
    }

    func testDecodesWsEvents() throws {
        for (raw, expectedType) in [
            (#"{"type":"partial","sessionId":"abc","content":"chunk"}"#, "partial"),
            (#"{"type":"status","sessionId":"abc","status":"streaming"}"#, "status"),
            (#"{"type":"subscribed","sessionId":"abc","status":"inactive","sequence":42}"#, "subscribed"),
            (#"{"type":"session_list","sessions":[]}"#, "session_list"),
        ] {
            let event = try JSONDecoder().decode(WsEvent.self, from: Data(raw.utf8))
            XCTAssertEqual(event.type, expectedType)
        }
    }

    func testCompactAge() {
        let now = ISO8601.date("2026-09-11T12:00:00.000Z")!
        XCTAssertEqual(ISO8601.compactAge("2026-09-11T11:59:40.000Z", now: now), "now")
        XCTAssertEqual(ISO8601.compactAge("2026-09-11T11:30:00.000Z", now: now), "30m")
        XCTAssertEqual(ISO8601.compactAge("2026-09-11T06:00:00.000Z", now: now), "6h")
        XCTAssertEqual(ISO8601.compactAge("2026-09-01T12:00:00.000Z", now: now), "10d")
        XCTAssertEqual(ISO8601.compactAge(nil, now: now), "")
        // Dates without fractional seconds must also parse
        XCTAssertNotNil(ISO8601.date("2026-09-11T12:00:00Z"))
    }

    func testDecodesEffectiveIdentity() throws {
        let json = """
        {"identity":{"id":1357913634,"name":"bux","token":"prf_4de45a242d2d",
        "displayName":"Barry Bux","defaultCodingAgent":"cursor","defaultModel":"claude-opus-5"},
        "source":"repo","repoRoot":"/Users/tyler/repos/barry"}
        """
        let effective = try JSONDecoder().decode(EffectiveIdentity.self, from: Data(json.utf8))
        XCTAssertEqual(effective.identity.defaultCodingAgent, "cursor")
        XCTAssertEqual(effective.identity.defaultModel, "claude-opus-5")
        XCTAssertEqual(effective.defaultProvider, .cursor)
    }

    /// Regression: defaultProvider originally referenced defaultCodingAgent
    /// at the wrong nesting level and failed to compile — this test exists
    /// so the correct nesting (identity.defaultCodingAgent) never drifts
    /// back to the broken shape silently.
    func testEffectiveIdentityDefaultsToClaudeWhenAgentUnset() throws {
        let json = """
        {"identity":{"id":1,"name":"default","token":"t","displayName":"Default",
        "defaultCodingAgent":null,"defaultModel":null},"source":"global","repoRoot":null}
        """
        let effective = try JSONDecoder().decode(EffectiveIdentity.self, from: Data(json.utf8))
        XCTAssertEqual(effective.defaultProvider, .claude)
        XCTAssertNil(effective.identity.defaultModel)
    }

    func testDecodesModelsResponse() throws {
        let json = """
        {"providers":{"claude":{"default":null,"small":"claude-haiku-4-5",
        "models":[{"id":"claude-opus-5","label":"Opus 5"},{"id":"claude-sonnet-5","label":"Sonnet 5"}]},
        "codex":{"default":null,"small":null,"models":[{"id":"gpt-5.6-sol","label":"GPT-5.6 Sol"}]}}}
        """
        let response = try JSONDecoder().decode(ModelsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.models(for: .claude).count, 2)
        XCTAssertEqual(response.models(for: .claude).first?.id, "claude-opus-5")
        XCTAssertEqual(response.models(for: .codex).count, 1)
        XCTAssertTrue(response.models(for: .ollama).isEmpty, "unlisted provider should yield an empty list, not crash")
    }

    func testDecodesTraitsResponse() throws {
        let json = """
        {"traits":[{"name":"ableton","description":"Ableton Live session control, MIDI sequencing, audio analysis, and mixing tools",
        "tools":[],"namespaces":["ableton"],"access":"readwrite","skills":["effects-chain","mixing"],
        "instructions":[],"scope":{},"scopeNames":[],"bag":"ableton"},
        {"name":"actions","description":"Validated procedures — find and run Barry actions",
        "tools":[],"namespaces":["actions"],"access":"readwrite","skills":[],"instructions":[],
        "scope":{},"scopeNames":[],"bag":"actions"}]}
        """
        let response = try JSONDecoder().decode(TraitsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.traits.count, 2)
        XCTAssertEqual(response.traits[0].name, "ableton")
        XCTAssertEqual(response.traits[0].namespaces, ["ableton"])
        XCTAssertTrue(response.traits[0].description.contains("MIDI"))
        XCTAssertEqual(response.traits[1].id, "actions")
    }

    func testServerConfigWebSocketURL() {
        let http = ServerConfig(baseURL: "http://127.0.0.1:9429", hostHeader: "", secret: "")
        XCTAssertEqual(http.webSocketURL?.absoluteString, "ws://127.0.0.1:9429/api/v1/ws")
        let https = ServerConfig(baseURL: "https://barry.works", hostHeader: "", secret: "")
        XCTAssertEqual(https.webSocketURL?.absoluteString, "wss://barry.works/api/v1/ws")
    }

    /// Regression: a New Session failure showed no visible feedback at all
    /// -- traced to two compounding bugs: the error Section rendered below
    /// the fold in the Form (fixed separately, now an .alert), and this
    /// message-extraction logic not handling the API's actual real error
    /// shapes. The server is genuinely inconsistent: RFC 7807 problem+json
    /// ({title, detail}) on some routes, a plain {error} on others -- both
    /// fixtures below are real shapes pulled from the live API, not
    /// invented ones.
    func testBarryErrorExtractsReadableDetailFromProblemJSON() {
        let body = #"{"type":"about:blank","title":"Failed to create draft session","status":500,"instance":"/api/v1/sessions/draft"}"#
        let error = BarryError.http(500, body)
        XCTAssertEqual(error.errorDescription, "Server error 500: Failed to create draft session")
    }

    func testBarryErrorExtractsReadableDetailFromPlainErrorShape() {
        let body = #"{"ok":false,"error":"Session has no working directory. Set repoPath in request body or update session first."}"#
        let error = BarryError.http(400, body)
        XCTAssertEqual(error.errorDescription, "Server error 400: Session has no working directory. Set repoPath in request body or update session first.")
    }

    func testBarryErrorPrefersDetailOverTitleWhenBothPresent() {
        let body = #"{"title":"Invalid request","detail":"systemPrompt: Invalid input: expected string, received undefined"}"#
        let error = BarryError.http(400, body)
        XCTAssertEqual(error.errorDescription, "Server error 400: systemPrompt: Invalid input: expected string, received undefined")
    }

    func testBarryErrorFallsBackToRawBodyWhenUnparseable() {
        let error = BarryError.http(502, "Bad Gateway")
        XCTAssertEqual(error.errorDescription, "Server error 502: Bad Gateway")
    }

    func testBarryErrorHandlesEmptyBody() {
        let error = BarryError.http(503, "")
        XCTAssertEqual(error.errorDescription, "Server error 503")
    }
}

/// Integration tests against the real local API. These make the client's
/// contract executable: they fail if the API's real shapes drift from the
/// models. Skipped automatically when the API is unreachable.
final class LiveAPITests: XCTestCase {
    let config = ServerConfig(baseURL: "http://127.0.0.1:9429", hostHeader: "", secret: "")

    private func requireServer() async throws {
        let client = BarryClient(config: config)
        do {
            _ = try await client.health()
        } catch {
            throw XCTSkip("Local barry.works proxy not reachable: \(error)")
        }
    }

    func testListsRealSessions() async throws {
        try await requireServer()
        let page = try await BarryClient(config: config).sessions(limit: 5)
        XCTAssertFalse(page.sessions.isEmpty, "expected at least one session with messages")
        for s in page.sessions {
            XCTAssertFalse(s.id.isEmpty)
            XCTAssertFalse(s.name.isEmpty)
        }
    }

    func testFetchesRealMessagesIncrementally() async throws {
        try await requireServer()
        let client = BarryClient(config: config)
        guard let session = try await client.sessions(limit: 1).sessions.first else {
            throw XCTSkip("no sessions")
        }
        let all = try await client.messages(sessionId: session.id)
        XCTAssertFalse(all.messages.isEmpty)
        // Sequences strictly increase — the app's incremental poll relies on it.
        let sequences = all.messages.map(\.sequence)
        XCTAssertEqual(sequences, sequences.sorted())
        // Incremental fetch returns only newer rows.
        if let last = sequences.last, sequences.count > 1 {
            let after = try await client.messages(sessionId: session.id, after: last)
            XCTAssertTrue(after.messages.allSatisfy { $0.sequence > last })
        }
    }

    func testFetchesRepos() async throws {
        try await requireServer()
        let repos = try await BarryClient(config: config).repos()
        XCTAssertFalse(repos.isEmpty)
    }

    /// Regression: createDraft() omitted `systemPrompt`, which the server
    /// requires (non-empty string) — every draft-session creation 400'd in
    /// the field with "systemPrompt: Invalid input: expected string,
    /// received undefined", caught only by hand-testing on a real device
    func testFetchesRealModelsForClaude() async throws {
        try await requireServer()
        let response = try await BarryClient(config: config).models()
        let claudeModels = response.models(for: .claude)
        XCTAssertFalse(claudeModels.isEmpty, "expected at least one real Claude model")
        XCTAssertTrue(claudeModels.allSatisfy { !$0.id.isEmpty && !$0.label.isEmpty })
    }

    func testFetchesRealTraits() async throws {
        try await requireServer()
        let traits = try await BarryClient(config: config).traits()
        XCTAssertFalse(traits.isEmpty, "expected at least one real trait")
        XCTAssertTrue(traits.allSatisfy { !$0.name.isEmpty && !$0.description.isEmpty })
    }

    func testResolvesRealEffectiveIdentity() async throws {
        try await requireServer()
        let client = BarryClient(config: config)
        guard let repo = try await client.repos().first else {
            throw XCTSkip("no repos configured")
        }
        let effective = try await client.effectiveIdentity(repoPath: repo.path)
        // defaultProvider always resolves to something real, even if the
        // server returns no explicit defaultCodingAgent (falls back to .claude).
        XCTAssertTrue(ProviderId.allCases.contains(effective.defaultProvider))
    }

    /// because no test exercised the actual network call. This creates one
    /// real (harmless, self-archiving) session end-to-end to close that gap.
    func testCreatesDraftSessionEndToEnd() async throws {
        try await requireServer()
        let client = BarryClient(config: config)
        guard let repo = try await client.repos().first else {
            throw XCTSkip("no repos configured")
        }
        let session = try await client.createDraft(
            repoPath: repo.path,
            systemPrompt: "iOS integration test — safe to ignore/archive",
            name: "ios-test-\(Int(Date().timeIntervalSince1970))",
            provider: nil,
            model: nil
        )
        XCTAssertFalse(session.id.isEmpty)
        // Clean up: this test's purpose is to exercise the network call and
        // its request shape, not to leave a session behind for a human to
        // notice and wonder about.
        try? await client.archiveSession(id: session.id)
    }
}
