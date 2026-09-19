import Foundation
import SwiftUI

/// State for one open conversation.
///
/// Durable truth is the REST message log. On open, only the most recent
/// page loads — a long-running session can carry hundreds of messages, and
/// rendering all of them up front is both slow and pointless when the user
/// only ever looks at the tail. Scrolling up pages in older history; the
/// socket adds streaming previews and tells us when to poll immediately.
@MainActor
final class ChatStore: ObservableObject {
    let session: Session
    @Published var messages: [Message] = []
    /// `messages` collapsed into single rows and grouped tool runs -- what
    /// `ChatView` actually renders. Computed rather than cached: message
    /// arrays here are at most a couple hundred rows (paged), so regrouping
    /// on every publish is cheap, and it keeps this as the single source of
    /// truth instead of a second piece of state that could drift from
    /// `messages`.
    var groupedMessages: [MessageStreamItem] { MessageGrouping.group(messages) }

    /// Sequence numbers of every loaded user message, oldest first -- the
    /// jump targets for the previous/next-user-message arrows. Derived, not
    /// stored: same reasoning as `groupedMessages`, this is at most a
    /// couple hundred entries even on a long session, cheap to recompute on
    /// every publish, and it keeps `messages` the single source of truth
    /// rather than risking a second array drifting out of sync with it.
    var userMessageSequences: [Int] { messages.filter(\.isUser).map(\.sequence) }

    @Published var streamingText = ""
    @Published var isWorking = false
    @Published var pendingSends: [String] = []
    @Published var loadError: String?
    @Published var initialLoadDone = false
    @Published var hasOlderMessages = false
    @Published var isLoadingOlder = false

    private let client: BarryClient
    private var socket: BarrySocket?
    private var pollTimer: Timer?
    private var newestSequence: Int?
    private var oldestSequence: Int?
    private var pollInFlight = false

    /// Messages fetched per page — enough to fill a screen without a visible
    /// gap, small enough that opening a long session stays instant.
    private let pageSize = 60

    init(session: Session, client: BarryClient) {
        self.session = session
        self.client = client
    }

    func start(config: ServerConfig) {
        Task { await loadInitial() }
        let socket = BarrySocket(config: config)
        socket.onEvent = { [weak self] event in self?.handle(event) }
        socket.connect()
        socket.subscribe(sessionId: session.id)
        self.socket = socket
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.pollNewer() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        socket?.close()
        socket = nil
    }

    private func handle(_ event: BarrySocket.Event) {
        switch event {
        case .streamingDelta(let id, let text) where id == session.id:
            streamingText += text
            isWorking = true
        case .activity(let id) where id == session.id:
            Task { await pollNewer() }
        case .status(let id, let status) where id == session.id:
            isWorking = (status == "streaming" || status == "starting")
            if !isWorking { streamingText = "" }
            Task { await pollNewer() }
        default:
            break
        }
    }

    /// First fetch: the tail of the conversation.
    func loadInitial() async {
        do {
            let page = try await client.messages(sessionId: session.id, limit: pageSize)
            messages = page.messages
            newestSequence = messages.last?.sequence
            oldestSequence = messages.first?.sequence
            // The server signals more-forward via hasMore on an unbounded
            // query; for the initial (most-recent) page a full page means
            // older history likely exists.
            hasOlderMessages = page.messages.count == pageSize
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        initialLoadDone = true
    }

    /// Scrolled to the top: fetch the page before what's loaded.
    func loadOlder() async {
        guard hasOlderMessages, !isLoadingOlder, let oldest = oldestSequence else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let page = try await client.messages(sessionId: session.id, before: oldest, limit: pageSize)
            let known = Set(messages.map(\.sequence))
            let fresh = page.messages.filter { !known.contains($0.sequence) }
            messages.insert(contentsOf: fresh, at: 0)
            oldestSequence = messages.first?.sequence
            hasOlderMessages = fresh.count == pageSize
        } catch {
            // Leave hasOlderMessages as-is; the next scroll-to-top retries.
        }
    }

    /// Poll forward for anything newer than what's loaded.
    func pollNewer() async {
        guard !pollInFlight else { return }
        pollInFlight = true
        defer { pollInFlight = false }
        do {
            let page = try await client.messages(sessionId: session.id, after: newestSequence)
            if !page.messages.isEmpty {
                let known = Set(messages.map(\.sequence))
                let fresh = page.messages.filter { !known.contains($0.sequence) }
                messages.append(contentsOf: fresh)
                newestSequence = messages.last?.sequence
                if oldestSequence == nil { oldestSequence = messages.first?.sequence }
                reconcilePending(with: fresh)
                // New durable content replaces the preview that announced it.
                if fresh.contains(where: { $0.isAssistant }) { streamingText = "" }
            }
            loadError = nil
        } catch {
            if messages.isEmpty { loadError = error.localizedDescription }
        }
    }

    func send(_ text: String, clientMessageId: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        pendingSends.append(trimmed)
        isWorking = true
        loadError = nil
        do {
            try await client.sendMessage(sessionId: session.id, content: trimmed, clientMessageId: clientMessageId)
            await pollNewer()
            return true
        } catch {
            pendingSends.removeAll { $0 == trimmed }
            isWorking = false
            loadError = error.localizedDescription
            return false
        }
    }

    /// Drop optimistic rows once the server's copy of the same text arrives.
    private func reconcilePending(with fresh: [Message]) {
        guard !pendingSends.isEmpty else { return }
        for message in fresh where message.isUser {
            if let index = pendingSends.firstIndex(of: message.content ?? "") {
                pendingSends.remove(at: index)
            }
        }
    }

    func detail(for message: Message) async -> MessageDetail? {
        try? await client.messageDetail(sessionId: session.id, sequence: message.sequence)
    }
}
