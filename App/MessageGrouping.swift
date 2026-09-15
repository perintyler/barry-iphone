import Foundation

/// One row of the chat's message stream after grouping: either a message
/// rendered on its own (unchanged from today), or a run of consecutive
/// same-tool calls collapsed into one card.
///
/// `Identifiable` keys on the first message's sequence -- stable across
/// re-grouping as new messages stream in, since a run's start point never
/// moves once assigned (only its end can grow).
enum MessageStreamItem: Identifiable {
    case single(Message)
    case group(ToolRun)

    var id: Int {
        switch self {
        case .single(let message): return message.sequence
        case .group(let run): return run.id
        }
    }
}

/// A run of 3+ consecutive `tool_start` messages sharing one tool name.
struct ToolRun: Identifiable, Equatable {
    let toolName: String
    let messages: [Message]

    var id: Int { messages.first?.sequence ?? 0 }
    var count: Int { messages.count }
}

enum MessageGrouping {
    /// A run must be at least this long before it collapses into a group.
    /// Below this, per-mockup: "the card adds a tap-to-expand step that two
    /// isolated calls don't need; the payoff only shows up past a handful
    /// in a row."
    static let minimumRunLength = 3

    /// Collapses consecutive same-tool-name runs (length >= `minimumRunLength`)
    /// into `.group` items; everything else -- user/assistant text, isolated
    /// tool calls, and runs of 1-2 -- passes through as `.single`, in the
    /// original order.
    ///
    /// The rule is deliberately narrow: a run breaks the moment assistant
    /// text OR a different tool name appears, so grouping never hides what
    /// the agent said, only how many times it repeated one kind of action.
    static func group(_ messages: [Message]) -> [MessageStreamItem] {
        var items: [MessageStreamItem] = []
        var pending: [Message] = []

        func flush() {
            guard !pending.isEmpty else { return }
            if pending.count >= minimumRunLength, let name = pending.first?.name {
                items.append(.group(ToolRun(toolName: name, messages: pending)))
            } else {
                items.append(contentsOf: pending.map(MessageStreamItem.single))
            }
            pending = []
        }

        for message in messages {
            if message.isTool, let name = message.name {
                if let lastName = pending.last?.name, lastName == name {
                    pending.append(message)
                } else {
                    flush()
                    pending = [message]
                }
            } else {
                flush()
                items.append(.single(message))
            }
        }
        flush()

        return items
    }
}
