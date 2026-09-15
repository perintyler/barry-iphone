import SwiftUI

/// Tracks how far the message list is scrolled from its bottom edge, using a
/// single invisible marker's frame rather than per-row observation --
/// `LazyVStack` only realizes on-screen rows, and reading a `GeometryReader`
/// frame on every row would force them all to materialize just to report
/// position, defeating the laziness that makes a long session's history
/// affordable in the first place. One marker, one preference write per
/// scroll tick, is the entire cost.
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Attach to the bottom sentinel view inside the scrollable content. Reports
/// that sentinel's distance below the scroll view's own visible bottom edge
/// -- 0 (or negative, already past it) means genuinely at the bottom; a
/// growing positive number means the user has scrolled up away from it.
struct BottomSentinelReader: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ScrollOffsetKey.self,
                value: geo.frame(in: .named("messagesScroll")).minY
            )
        }
        .frame(height: 1)
    }
}

/// Tracks which loaded user messages are currently on-screen, using
/// `onAppear`/`onDisappear` on each `UserBubble` rather than a
/// `GeometryReader` per row -- those two callbacks are how `LazyVStack`
/// already signals realize/derealize for free, so this adds no extra
/// geometry pass over what the scroll view is already doing to decide what
/// to render.
///
/// Backed by a `Set` rather than a single "topmost" value: rows can appear
/// and disappear out of order during fast scrolling or a bounce-back
/// animation, and a set is trivially safe to update from either callback in
/// any order, whereas tracking just one topmost id would need extra logic
/// to avoid briefly reporting the wrong row mid-scroll.
@MainActor
final class VisibleUserMessages: ObservableObject {
    @Published private(set) var visible: Set<Int> = []

    func markVisible(_ sequence: Int) { visible.insert(sequence) }
    func markHidden(_ sequence: Int) { visible.remove(sequence) }

    /// The topmost currently-visible user message, if any -- "topmost" by
    /// sequence order among what's visible, which matches reading order
    /// since sequences only ever increase top-to-bottom in a loaded window.
    func topmostVisible(in ordered: [Int]) -> Int? {
        ordered.first { visible.contains($0) }
    }
}
