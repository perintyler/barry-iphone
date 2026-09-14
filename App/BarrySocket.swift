import Foundation

/// Live-update channel. The REST poller is the source of truth; this socket
/// only makes the app feel instant: streaming previews (`partial` deltas),
/// nudges to poll right now (`text`, `tool_start`), and status changes.
///
/// CLI-started sessions never broadcast here (the API only knows sessions it
/// spawned), so everything must keep working when this stays silent.
@MainActor
final class BarrySocket {
    enum Event {
        case streamingDelta(sessionId: String, text: String)
        case activity(sessionId: String)          // something happened; poll now
        case status(sessionId: String, status: String)
        case connectionChanged(Bool)
    }

    var onEvent: ((Event) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var config: ServerConfig
    private var subscribedSessionId: String?
    private var reconnectAttempt = 0
    private var closed = false

    init(config: ServerConfig) {
        self.config = config
    }

    func connect() {
        closed = false
        guard let url = config.webSocketURL else { return }
        var req = URLRequest(url: url)
        config.apply(to: &req)
        let task = URLSession.shared.webSocketTask(with: req)
        self.task = task
        task.resume()
        onEvent?(.connectionChanged(true))
        receiveLoop(task)
        if let id = subscribedSessionId { send(["type": "subscribe", "sessionId": id]) }
    }

    func close() {
        closed = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func subscribe(sessionId: String) {
        if let previous = subscribedSessionId, previous != sessionId {
            send(["type": "unsubscribe", "sessionId": previous])
        }
        subscribedSessionId = sessionId
        send(["type": "subscribe", "sessionId": sessionId])
    }

    private func send(_ payload: [String: Any]) {
        guard let task, let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.task === task else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message, let data = text.data(using: .utf8),
                       let event = try? JSONDecoder().decode(WsEvent.self, from: data) {
                        self.handle(event)
                    }
                    self.receiveLoop(task)
                case .failure:
                    self.onEvent?(.connectionChanged(false))
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handle(_ event: WsEvent) {
        reconnectAttempt = 0
        guard let sessionId = event.sessionId ?? subscribedSessionId else { return }
        switch event.type {
        case "partial":
            if let content = event.content, !content.isEmpty {
                onEvent?(.streamingDelta(sessionId: sessionId, text: content))
            }
        case "text", "tool_start", "tool_result", "result", "task_finished":
            onEvent?(.activity(sessionId: sessionId))
        case "status":
            if let status = event.status { onEvent?(.status(sessionId: sessionId, status: status)) }
        default:
            break
        }
    }

    private func scheduleReconnect() {
        guard !closed else { return }
        let delay = min(30.0, pow(2.0, Double(reconnectAttempt)))
        reconnectAttempt += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !self.closed else { return }
            self.connect()
        }
    }
}
