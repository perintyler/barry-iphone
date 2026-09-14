import Foundation

enum BarryError: LocalizedError {
    case badURL
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid server URL"
        case .http(let code, let body):
            return "Server error \(code)" + (body.isEmpty ? "" : ": \(body.prefix(200))")
        case .decoding(let detail): return "Unexpected response: \(detail)"
        }
    }
}

/// REST client for the Barry API (through the barry.works proxy).
struct BarryClient {
    var config: ServerConfig
    var urlSession: URLSession = .shared

    // MARK: Requests

    private func get<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        guard let req = config.request(path: path, query: query) else { throw BarryError.badURL }
        return try await run(type, req)
    }

    private func post<T: Decodable>(_ type: T.Type, path: String, body: [String: Any]) async throws -> T {
        guard var req = config.request(path: path) else { throw BarryError.badURL }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await run(type, req)
    }

    private func run<T: Decodable>(_ type: T.Type, _ req: URLRequest) async throws -> T {
        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw BarryError.decoding("no response") }
        guard (200..<300).contains(http.statusCode) else {
            throw BarryError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BarryError.decoding(String(describing: error))
        }
    }

    // MARK: API

    func health() async throws -> Bool {
        struct Health: Decodable { let ok: Bool }
        return try await get(Health.self, path: "/health").ok
    }

    func sessions(limit: Int = 50, cursor: String? = nil) async throws -> SessionsPage {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "hasMessages", value: "true"),
        ]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await get(SessionsPage.self, path: "/api/v1/sessions", query: query)
    }

    func session(id: String) async throws -> Session {
        try await get(Session.self, path: "/api/v1/sessions/\(id)")
    }

    /// Persisted messages. Pass `after` to page forward (poll for new
    /// messages) or `before` to page backward (scroll up into older
    /// history) — never both. With neither, the server returns the MOST
    /// RECENT `limit` messages in chronological order, which is what the
    /// app wants on first open: a long-running session can carry hundreds
    /// of messages, and opening chat should feel instant, not block on
    /// rendering all of them.
    func messages(sessionId: String, after: Int? = nil, before: Int? = nil, limit: Int = 60) async throws -> MessagesPage {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "summary", value: "1"),
        ]
        if let after { query.append(URLQueryItem(name: "after", value: String(after))) }
        if let before { query.append(URLQueryItem(name: "before", value: String(before))) }
        return try await get(MessagesPage.self, path: "/api/v1/sessions/\(sessionId)/messages", query: query)
    }

    func messageDetail(sessionId: String, sequence: Int) async throws -> MessageDetail {
        try await get(MessageDetail.self, path: "/api/v1/sessions/\(sessionId)/messages/\(sequence)/detail")
    }

    /// Send a message. Starts the session server-side if it is not active.
    func sendMessage(sessionId: String, content: String) async throws {
        struct Ack: Decodable { let ok: Bool }
        _ = try await post(Ack.self, path: "/api/v1/sessions/\(sessionId)/message", body: ["content": content])
    }

    func repos() async throws -> [Repo] {
        try await get(ReposPage.self, path: "/api/v1/repos").repos
    }

    /// Create a draft session; returns the new session.
    func createDraft(repoPath: String, name: String?, provider: String?, model: String?) async throws -> Session {
        var body: [String: Any] = ["repoPath": repoPath]
        if let name, !name.isEmpty { body["name"] = name }
        if let provider, !provider.isEmpty { body["provider"] = provider }
        if let model, !model.isEmpty { body["model"] = model }
        return try await post(Session.self, path: "/api/v1/sessions/draft", body: body)
    }

    func stopSession(id: String) async throws {
        struct Ack: Decodable { let ok: Bool }
        _ = try await post(Ack.self, path: "/api/v1/sessions/\(id)/stop", body: [:])
    }

    func archiveSession(id: String) async throws {
        struct Ack: Decodable { let ok: Bool }
        _ = try await post(Ack.self, path: "/api/v1/sessions/\(id)/archive", body: [:])
    }
}
