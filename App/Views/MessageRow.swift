import SwiftUI

/// Renders one item of the grouped message stream (see `MessageGrouping`):
/// a single persisted message -- user bubble, assistant text, or tool line,
/// same as before grouping existed -- or a collapsed run of consecutive
/// same-tool calls.
struct MessageRow: View {
    let item: MessageStreamItem
    @ObservedObject var chat: ChatStore

    var body: some View {
        switch item {
        case .single(let message):
            if message.isUser {
                UserBubble(text: message.content ?? "", pending: false)
            } else if message.isAssistant {
                AssistantText(text: message.content ?? "")
            } else if message.isTool {
                ToolRow(message: message, chat: chat)
            }
        case .group(let run):
            ToolRunGroupView(run: run, chat: chat)
        }
    }
}

struct UserBubble: View {
    let text: String
    let pending: Bool

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.accent.opacity(pending ? 0.55 : 1.0), in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct AssistantText: View {
    let text: String

    var body: some View {
        Text(markdown: text)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Text {
    /// Best-effort markdown; falls back to plain text on parse failure.
    init(markdown: String) {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            self.init(attributed)
        } else {
            self.init(verbatim: markdown)
        }
    }
}

/// One line per tool call, quiet by default, tap to inspect.
struct ToolRow: View {
    let message: Message
    @ObservedObject var chat: ChatStore
    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text(message.toolLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let hint = message.inputHint {
                    Text(hint)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            ToolDetailView(message: message, chat: chat)
        }
    }
}

struct ToolDetailView: View {
    let message: Message
    @ObservedObject var chat: ChatStore
    @State private var detail: MessageDetail?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Input", text: detail?.input?.text ?? message.input?.text)
                    section("Result", text: detail?.result?.text ?? message.result?.text)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(message.toolLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if message.hasDetail == true {
                    detail = await chat.detail(for: message)
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, text: String?) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - Grouped tool runs

/// A collapsed card for 3+ consecutive same-tool calls (see
/// `MessageGrouping`). Collapsed, it shows the tool name, a "× N" count, and
/// a generated preview line from the first couple calls' inputs -- same
/// visual language as `DiffView`'s and `BookkeepingView`'s collapsible
/// sections (chevron rotation, secondary-background card, tertiary detail
/// text). Expanded, it lists every call in the run in order; tapping one
/// opens the same `ToolDetailView` sheet an ungrouped `ToolRow` uses today,
/// so the per-call detail experience is identical either way.
struct ToolRunGroupView: View {
    let run: ToolRun
    @ObservedObject var chat: ChatStore
    @State private var expanded = false

    /// How many individual calls show before a "Show N more" reveal --
    /// keeps a freshly expanded 100-call run from dumping every row at once.
    private static let initialVisibleCount = 3

    @State private var visibleCount = ToolRunGroupView.initialVisibleCount

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                Divider().padding(.leading, 41)
                callList
            }
        }
        .padding(11)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
    }

    private var header: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Text(toolIcon)
                    .font(.system(size: 12))
                    .frame(width: 26, height: 26)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 1) {
                    (Text(run.toolName).fontWeight(.semibold)
                     + Text("  ×\u{a0}\(run.count)").foregroundStyle(.tertiary).fontWeight(.regular))
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    if let preview {
                        Text(preview)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
        }
        .buttonStyle(.plain)
        // On the header Button, not the outer VStack: when the card is
        // collapsed, this Button is the only interactive content inside
        // that VStack, so SwiftUI coalesces the whole card into ONE
        // accessibility element and only the identifier on the actual
        // interactive element (this Button) survives that coalescing --
        // an identifier placed on the outer container instead is silently
        // unreachable by a UI test's element query. "toolRunGroup" doubles
        // as both "the card exists, collapsed or not" and "the tappable
        // header" for that reason -- there's only ever one queryable
        // element here until it's expanded.
        .accessibilityIdentifier("toolRunGroup")
    }

    private var callList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(run.messages.prefix(visibleCount))) { message in
                ToolRunCallRow(message: message, chat: chat)
            }
            let remaining = run.count - visibleCount
            if remaining > 0 {
                Button("Show \(remaining) more") {
                    withAnimation(.easeOut(duration: 0.18)) { visibleCount = run.count }
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityIdentifier("toolRunGroupShowMore")
            }
        }
        .padding(.top, 9)
        .padding(.leading, 35)
    }

    /// First couple calls' input hints, so a collapsed card still says
    /// roughly what happened without opening it -- generated from
    /// `Message.inputHint`, the same per-call summary `ToolRow` shows today,
    /// not a hand-authored description.
    private var preview: String? {
        let hints = run.messages.prefix(3).compactMap(\.inputHint)
        guard !hints.isEmpty else { return nil }
        return hints.joined(separator: " · ")
    }

    /// Small per-tool glyph. The mockup's own worked example only shows
    /// Bash (💻); other common tools get a sensible pick, and anything
    /// unrecognized falls back to a generic tool glyph rather than guessing.
    private var toolIcon: String {
        switch run.toolName {
        case "Bash": return "💻"
        case "Read": return "📄"
        case "Write", "Edit": return "✏️"
        case "Grep", "Glob": return "🔍"
        case "WebFetch", "WebSearch": return "🌐"
        case "Agent", "Task": return "🤖"
        default: return "🔧"
        }
    }
}

/// One call within an expanded `ToolRunGroupView` -- a slimmer variant of
/// `ToolRow` (no leading chevron, smaller type to match the card's density)
/// that opens the same `ToolDetailView` sheet.
private struct ToolRunCallRow: View {
    let message: Message
    @ObservedObject var chat: ChatStore
    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 6) {
                if let hint = message.inputHint {
                    Text(hint)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(message.toolLabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            ToolDetailView(message: message, chat: chat)
        }
    }
}
