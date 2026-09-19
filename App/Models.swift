import Foundation

// MARK: - Session

/// One Barry session, as served by GET /api/v1/sessions.
struct Session: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
    let summary: String?
    let repoPath: String?
    let status: String
    let provider: String?
    let model: String?
    let messageCount: Int?
    let lastMessageAt: String?
    let statusUpdate: StatusUpdate?
    let createdAt: String
    let pinned: Bool?

    struct StatusUpdate: Decodable, Equatable {
        let summary: String
        let phase: String?
        let updatedAt: String
    }

    var repoName: String? {
        guard let repoPath, !repoPath.isEmpty else { return nil }
        return (repoPath as NSString).lastPathComponent
    }

    var isRunning: Bool { status == "running" }

    /// Best timestamp for "recent activity" ordering and display.
    var activityDate: Date {
        ISO8601.date(lastMessageAt) ?? ISO8601.date(createdAt) ?? .distantPast
    }
}

struct SessionsPage: Decodable {
    let sessions: [Session]
    let nextCursor: String?
}

// MARK: - Messages

/// One persisted message from GET /api/v1/sessions/:id/messages.
/// `type` is "text" (with a role) or "tool_start".
struct Message: Identifiable, Decodable, Equatable {
    let type: String
    let role: String?
    let content: String?
    let name: String?
    let input: LooseString?
    let result: LooseString?
    let hasDetail: Bool?
    let toolUseId: String?
    let sequence: Int
    let createdAt: String?

    var id: Int { sequence }

    var isUser: Bool { type == "text" && role == "user" }
    var isAssistant: Bool { type == "text" && role == "assistant" }
    var isTool: Bool { type == "tool_start" }

    /// Short human name for a tool: "mcp__git__status" -> "git status".
    /// Splits on the "__" NAMESPACE delimiter, not on every underscore —
    /// "mcp__session__set_current_session_name" must read as
    /// "session set_current_session_name", not have its own tool name
    /// word-mangled into "session set current session name".
    var toolLabel: String {
        guard let name else { return "tool" }
        if name.hasPrefix("mcp__") {
            let parts = name.components(separatedBy: "__").filter { !$0.isEmpty }
            if parts.count >= 3 { return parts.dropFirst().joined(separator: " ") }
        }
        return name
    }

    /// A one-line whisper of what the tool was asked to do -- the same
    /// truncated-input summary `ToolRow` shows per call, reused for a
    /// grouped tool run's collapsed preview line (see `MessageGrouping`).
    var inputHint: String? {
        guard let input = input?.text, !input.isEmpty else { return nil }
        let flat = input
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty, flat != "{}" else { return nil }
        return String(flat.prefix(60))
    }
}

struct MessagesPage: Decodable {
    let messages: [Message]
    let nextSequence: Int?
    let hasMore: Bool
}

/// Full tool input/result from GET /messages/:sequence/detail.
struct MessageDetail: Decodable {
    let ok: Bool
    let input: LooseString?
    let result: LooseString?
}

/// A field the API serves either as a JSON string or as a JSON object.
/// Summary mode truncates tool input to a string; full mode keeps the object.
struct LooseString: Decodable, Equatable {
    let text: String

    init(text: String) { self.text = text }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            text = s
        } else if let v = try? container.decode(JSONValue.self) {
            text = v.prettyPrinted
        } else {
            text = ""
        }
    }
}

/// Minimal JSON tree used to re-serialize arbitrary tool input for display.
enum JSONValue: Decodable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    var prettyPrinted: String {
        switch self {
        case .string(let s): return s
        case .number(let n):
            return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .bool(let b): return String(b)
        case .null: return "null"
        case .array(let a):
            return "[" + a.map(\.prettyPrinted).joined(separator: ", ") + "]"
        case .object(let o):
            return o.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.prettyPrinted)" }
                .joined(separator: "\n")
        }
    }
}

// MARK: - Repos

struct Repo: Identifiable, Decodable, Equatable {
    let id: Int
    let name: String
    let path: String
}

struct ReposPage: Decodable {
    let repos: [Repo]
}

// MARK: - Providers & Models

/// One selectable model from GET /api/v1/models.
struct ModelOption: Decodable, Equatable, Identifiable {
    let id: String
    let label: String
    let note: String?
}

/// Per-provider model catalog from GET /api/v1/models.
struct ProviderModels: Decodable {
    let label: String?
    let defaultModel: String?
    let models: [ModelOption]
    let stale: Bool?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case label, models, stale, source
        case defaultModel = "default"
    }
}

struct ModelsResponse: Decodable {
    let providers: [String: ProviderModels]

    var providerIDs: [String] {
        providers.keys.sorted()
    }

    func label(for provider: String) -> String {
        providers[provider]?.label ?? provider.capitalized
    }
}

/// GET /api/v1/identities/effective?repoPath=... — what a session would
/// actually use if nothing on the draft overrides it. Shown so "Default"
/// never has to mean "unknown to the user."
struct EffectiveIdentity: Decodable {
    let identity: Identity

    struct Identity: Decodable {
        let defaultCodingAgent: String?
        let defaultModel: String?
    }

    var defaultProvider: String {
        identity.defaultCodingAgent ?? "claude"
    }
}

// MARK: - Traits

/// One trait from GET /api/v1/traits. A trait is a named bundle of
/// tool/namespace access a session can be granted — this app only ever
/// shows and selects traits by name, so only the fields the UI reads are
/// modeled (the real payload also carries `tools`, `access`, `skills`,
/// `instructions`, `scope`, `scopeNames`, and `bag`, all server-internal
/// concerns this picker has no use for).
struct Trait: Decodable, Equatable, Identifiable {
    let name: String
    let description: String
    let namespaces: [String]

    var id: String { name }
}

struct TraitsResponse: Decodable {
    let traits: [Trait]
}

// MARK: - WebSocket events

/// Server -> client event on /api/v1/ws. Only the fields the app reads.
struct WsEvent: Decodable {
    let type: String
    let sessionId: String?
    let content: String?
    let role: String?
    let status: String?
    let sequence: Int?
    let name: String?
    let error: String?
}

// MARK: - Diff

/// The mode a diff view fetches: matches the server's `mode` query param.
enum DiffMode: String {
    case uncommitted
    case branch
    case commit
}

/// GET /api/v1/sessions/:id/diff — one shape for all three modes. The
/// server's real response only ever carries the fields relevant to the
/// mode requested (branch-only fields are absent for `mode=uncommitted`,
/// etc.), so every mode-specific field is optional here rather than
/// modeled as three separate response types -- one Decodable struct that
/// matches the one real endpoint, same house style as `Message` handling
/// both "text" and "tool_start" shapes in a single struct.
///
/// `diff` is RAW unified-diff text (`git diff --no-color`), unparsed by
/// the server -- `DiffParser.parse(_:)` turns it into `[DiffFile]`.
struct SessionDiff: Decodable, Equatable {
    let sessionId: String
    let repoPath: String
    let mode: String
    let diff: String
    let hasStagedChanges: Bool?
    let hasUnstagedChanges: Bool?
    let hasUntrackedFiles: Bool?
    let baseBranch: String?
    let currentBranch: String?
    let onMainBranch: Bool?
    let commit: String?

    /// UTF-8 byte size of the raw diff text -- the input to every
    /// threshold in `DiffThresholds` (auto-collapse, performance mode),
    /// which are all specified in bytes, not characters.
    var diffSizeBytes: Int { diff.utf8.count }
}

// MARK: - Dates

enum ISO8601 {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return fractional.date(from: s) ?? plain.date(from: s)
    }

    /// "2m", "3h", "4d" — compact relative time for list rows.
    static func compactAge(_ s: String?, now: Date = Date()) -> String {
        guard let d = date(s) else { return "" }
        let secs = max(0, now.timeIntervalSince(d))
        if secs < 60 { return "now" }
        if secs < 3600 { return "\(Int(secs / 60))m" }
        if secs < 86400 { return "\(Int(secs / 3600))h" }
        return "\(Int(secs / 86400))d"
    }
}
