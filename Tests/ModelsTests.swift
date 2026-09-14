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

    func testServerConfigWebSocketURL() {
        let http = ServerConfig(baseURL: "http://127.0.0.1:9429", hostHeader: "", secret: "")
        XCTAssertEqual(http.webSocketURL?.absoluteString, "ws://127.0.0.1:9429/api/v1/ws")
        let https = ServerConfig(baseURL: "https://barry.works", hostHeader: "", secret: "")
        XCTAssertEqual(https.webSocketURL?.absoluteString, "wss://barry.works/api/v1/ws")
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
}
