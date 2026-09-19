import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var chat: ChatStore
    @State private var draft = ""
    @State private var failedSend: (text: String, id: String)?
    @FocusState private var inputFocused: Bool
    @StateObject private var visibility = VisibleUserMessages()

    /// Distance (points) the bottom sentinel may sit below the scroll
    /// view's visible bottom edge and still count as "at the bottom" --
    /// large enough to absorb the last message's own height (so finishing a
    /// short scroll animation doesn't read as "still scrolled away") without
    /// being so large that a real intentional scroll-up gets mistaken for
    /// staying at the bottom.
    private static let nearBottomThreshold: CGFloat = 80

    @State private var isNearBottom = true
    /// Guards `onPreferenceChange(ScrollOffsetKey.self)` against transient
    /// geometry readings during the initial-load layout transition -- see
    /// that handler's own doc comment for why this exists.
    @State private var initialLoadSettled = false
    /// One step behind `isNearBottom` -- see the message-arrival handler's
    /// own doc comment for why this exists instead of reading the live
    /// value directly.
    @State private var wasNearBottomBeforeThisMessage = true

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
            ZStack(alignment: .bottomTrailing) {
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
                            MessageRow(item: item, chat: chat, visibility: visibility)
                                .id(item.id)
                        }
                        ForEach(chat.pendingSends, id: \.self) { text in
                            UserMessageRow(text: text, pending: true)
                        }
                        if let error = chat.loadError, !chat.messages.isEmpty {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("messageError")
                        }
                        if !chat.streamingText.isEmpty {
                            AssistantText(streaming: chat.streamingText)
                                .id("streaming")
                        } else if chat.isWorking {
                            WorkingIndicator()
                                .id("working")
                        }
                        BottomSentinelReader().id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .coordinateSpace(name: "messagesScroll")
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(ScrollOffsetKey.self) { bottomMinY in
                    // `bottomMinY` is the sentinel's Y position in the
                    // scroll view's own coordinate space -- since the
                    // scroll view fills its container, that space's height
                    // roughly tracks the visible viewport, so "sentinel at
                    // or above viewport height" is "at the bottom."
                    // Comparing against a small fixed threshold rather than
                    // 0 exactly absorbs sub-pixel scroll settling.
                    //
                    // Ignored entirely until `initialLoadSettled`: the
                    // initial page populates in one publish (empty -> ~60
                    // rows), and `defaultScrollAnchor(.bottom)` needs one or
                    // more layout passes to catch up to that growing
                    // content -- a fixed timer guessing how long that takes
                    // was tried and was genuinely flaky (verified against
                    // this session's own real ~60-message load: sometimes
                    // one pass was enough, sometimes it wasn't). Instead,
                    // `initialLoadSettled` only flips once a reading
                    // actually CONFIRMS the view is at the bottom, driven by
                    // real geometry rather than a guessed duration -- see
                    // that side of the assignment below.
                    guard initialLoadSettled else {
                        if bottomMinY < Self.nearBottomThreshold {
                            initialLoadSettled = true
                            isNearBottom = true
                        }
                        return
                    }
                    isNearBottom = bottomMinY < Self.nearBottomThreshold
                }
                .onChange(of: chat.initialLoadDone) {
                    guard chat.initialLoadDone else { return }
                    // Backstop only: `initialLoadSettled` normally flips
                    // off a real confirmed-at-bottom geometry reading (see
                    // the preference-change handler above). This exists so
                    // a session whose layout genuinely never reports a
                    // sub-threshold reading (an edge case, not the normal
                    // path) doesn't leave geometry updates ignored forever
                    // -- after a generous window, trust whatever's been
                    // measured so far rather than staying stuck.
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        if !initialLoadSettled { initialLoadSettled = true }
                    }
                }
                .onChange(of: chat.messages.last?.sequence) { oldValue, newValue in
                    // Keyed on the newest sequence, not the count: loading
                    // OLDER history also changes count, and must not yank
                    // the view back down while the user is scrolled up
                    // reading it. Now also gated on `wasNearBottomBeforeThisMessage`
                    // (captured BEFORE this new message grew the content),
                    // not the live `isNearBottom` read at the moment this
                    // fires -- `isNearBottom` is computed from the
                    // scroll-view geometry, and a just-arrived message that
                    // grows `LazyVStack`'s height moves the true bottom
                    // further away BEFORE the scroll position has a chance
                    // to follow it down, which briefly (and correctly, in
                    // isolation) reports `isNearBottom = false` against the
                    // NEW height even though the user was sitting right at
                    // the OLD bottom and never scrolled. Reading the stale
                    // live value here would skip the auto-scroll on new
                    // content precisely when it's most wanted -- an actively
                    // streaming session's tail growing while a user is
                    // reading it, exactly the case that motivated "stick to
                    // bottom" in the first place.
                    guard oldValue != nil, wasNearBottomBeforeThisMessage else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
                }
                .onChange(of: isNearBottom) { _, newValue in
                    // Track the LAST KNOWN state one step behind, so the
                    // message-arrival handler above can consult "was this
                    // near the bottom before the new content changed the
                    // measurement" rather than "is it near the bottom
                    // AFTER."
                    wasNearBottomBeforeThisMessage = newValue
                }
                .onChange(of: chat.streamingText) {
                    guard isNearBottom else { return }
                    proxy.scrollTo("bottom")
                }

                JumpControls(chat: chat, visibility: visibility, proxy: proxy, isNearBottom: isNearBottom)
                    .padding(.trailing, 14)
                    .padding(.bottom, 10)
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
                let id = failedSend.flatMap { $0.text == text ? $0.id : nil } ?? UUID().uuidString
                draft = ""
                failedSend = nil
                Task {
                    if !(await chat.send(text, clientMessageId: id)) {
                        failedSend = (text, id)
                        if draft.isEmpty { draft = text }
                    }
                }
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
