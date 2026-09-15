import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var chat: ChatStore
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private let session: Session

    /// `config` comes from the caller (which reads it from `AppStore`) rather
    /// than this view calling `ServerConfig.load()` itself: a `StateObject`
    /// initializes before `@EnvironmentObject` is available, and re-deriving
    /// config here would silently diverge from the app's single source of
    /// truth for server settings if the two ever disagreed.
    init(session: Session, config: ServerConfig) {
        self.session = session
        _chat = StateObject(wrappedValue: ChatStore(session: session, client: BarryClient(config: config)))
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesArea
            inputBar
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(session.name)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        StatusDot(status: chat.isWorking ? "running" : session.status)
                        Text(chat.isWorking ? "Working" : Theme.statusLabel(session.status))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    DiffView(session: session, config: store.config)
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .accessibilityIdentifier("diffViewButton")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    BookkeepingView(session: session)
                } label: {
                    Image(systemName: "list.bullet.clipboard")
                }
                .accessibilityIdentifier("bookkeepingViewButton")
            }
        }
        .task {
            chat.start(config: store.config)
        }
        .onDisappear { chat.stop() }
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !chat.initialLoadDone {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if let error = chat.loadError, chat.messages.isEmpty {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if chat.hasOlderMessages {
                        olderHistoryTrigger
                    }
                    ForEach(chat.groupedMessages) { item in
                        MessageRow(item: item, chat: chat)
                            .id(item.id)
                    }
                    ForEach(chat.pendingSends, id: \.self) { text in
                        UserBubble(text: text, pending: true)
                    }
                    if !chat.streamingText.isEmpty {
                        AssistantText(text: chat.streamingText)
                            .id("streaming")
                    } else if chat.isWorking {
                        WorkingIndicator()
                            .id("working")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.last?.sequence) {
                // Keyed on the newest sequence, not the count: loading OLDER
                // history also changes count, and must not yank the view
                // back down to the bottom while the user is scrolled up
                // reading it.
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
            }
            .onChange(of: chat.streamingText) {
                proxy.scrollTo("bottom")
            }
        }
    }

    /// Sits at the top of the scroll content; appearing (user scrolled up)
    /// triggers loading the previous page of history.
    private var olderHistoryTrigger: some View {
        HStack {
            Spacer()
            if chat.isLoadingOlder {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
        .frame(height: 28)
        .onAppear { Task { await chat.loadOlder() } }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 20))
                .focused($inputFocused)
                .accessibilityIdentifier("messageInput")
            Button {
                let text = draft
                draft = ""
                Task { await chat.send(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("sendButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// Three softly pulsing dots while Barry is working with no preview text yet.
struct WorkingIndicator: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase ? 1.0 : 0.55)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2),
                        value: phase
                    )
            }
        }
        .padding(.vertical, 6)
        .onAppear { phase = true }
        .accessibilityIdentifier("workingIndicator")
    }
}
