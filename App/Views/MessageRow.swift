import SwiftUI

/// Renders one persisted message: user bubble, assistant text, or tool line.
struct MessageRow: View {
    let message: Message
    @ObservedObject var chat: ChatStore

    var body: some View {
        if message.isUser {
            UserBubble(text: message.content ?? "", pending: false)
        } else if message.isAssistant {
            AssistantText(text: message.content ?? "")
        } else if message.isTool {
            ToolRow(message: message, chat: chat)
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
                if let hint = inputHint {
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

    /// A one-line whisper of what the tool was asked to do.
    private var inputHint: String? {
        guard let input = message.input?.text, !input.isEmpty else { return nil }
        let flat = input
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty, flat != "{}" else { return nil }
        return String(flat.prefix(60))
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
