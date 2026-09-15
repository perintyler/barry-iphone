import Foundation

/// Pure navigation logic for the previous/next-user-message jump arrows --
/// separated from `JumpControls` (the view) so the boundary conditions
/// (first message, last message, nothing visible, no messages at all) can
/// be tested directly against plain values instead of through SwiftUI's
/// view lifecycle and `@ObservedObject` machinery.
struct JumpNavigation {
    /// All loaded user-message sequences, oldest first.
    let sequences: [Int]
    /// The topmost currently-visible user message, if any is on-screen.
    let topmostVisible: Int?
    /// Whether the scroll position is already at (or very near) the
    /// bottom of the conversation.
    let isNearBottom: Bool

    private var currentIndex: Int? {
        guard let topmostVisible else { return nil }
        return sequences.firstIndex(of: topmostVisible)
    }

    var hasPrevious: Bool {
        guard let currentIndex else { return !sequences.isEmpty }
        return currentIndex > 0
    }

    /// "Next" is meaningful whenever we're not already looking at the
    /// newest user message -- covers both "somewhere in the middle" and
    /// "scrolled below the last user message, into trailing assistant/tool
    /// content" (no `currentIndex` because no user bubble is on-screen, but
    /// there's still a real newest one to jump back to if we're not already
    /// at the bottom).
    ///
    /// Deliberately independent of `sequences.isEmpty`: a "scroll to the
    /// bottom" affordance is a plain scroll-position fact, not a
    /// user-message-navigation fact -- a real session with a long tail of
    /// assistant/tool content and zero user messages loaded on the current
    /// page (a real, confirmed-live case: a page can legitimately be one
    /// long uninterrupted assistant reply) must still be able to jump back
    /// down. Gating this on `sequences` not being empty was the actual bug
    /// this comment used to describe as intentional and was wrong -- caught
    /// via a real device screenshot showing the arrow silently missing on
    /// exactly that kind of session.
    var hasNext: Bool {
        guard let currentIndex else { return !isNearBottom }
        // Even on the newest user message, there can be a long reply below
        // it (tool calls, a big assistant response) between here and the
        // true bottom -- `!isNearBottom` catches "still worth offering a
        // way down" in that case, not just "there's a later user message."
        return currentIndex < sequences.count - 1 || !isNearBottom
    }

    /// The sequence to scroll to for "previous" -- nil only means "there is
    /// no earlier message," never "scroll to bottom" (unlike `nextTarget`,
    /// bottom is never a meaningful destination for "previous").
    var previousTarget: Int? {
        guard let currentIndex, currentIndex > 0 else { return sequences.last }
        return sequences[currentIndex - 1]
    }

    /// The sequence to scroll to for "next" -- nil means "scroll to
    /// bottom" instead of "there is no next message": once past the newest
    /// user message, the useful destination is the end of the
    /// conversation, not a specific message id.
    var nextTarget: Int? {
        guard let currentIndex, currentIndex < sequences.count - 1 else { return nil }
        return sequences[currentIndex + 1]
    }
}
