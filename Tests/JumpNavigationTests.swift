import XCTest
@testable import Barry

final class JumpNavigationTests: XCTestCase {

    // MARK: No messages at all

    func testNoMessagesHasNeitherDirection() {
        let nav = JumpNavigation(sequences: [], topmostVisible: nil, isNearBottom: true)
        XCTAssertFalse(nav.hasPrevious)
        XCTAssertFalse(nav.hasNext)
    }

    /// Regression test for a real bug found via a live-device screenshot:
    /// a session whose loaded page has ZERO user messages (a real,
    /// confirmed case -- one long uninterrupted assistant reply can fill an
    /// entire page) must still be able to show a "scroll to bottom" arrow
    /// when scrolled away from the bottom. `hasNext`'s nil-`currentIndex`
    /// branch used to require `!sequences.isEmpty`, which silently hid the
    /// bottom arrow forever on exactly this kind of session -- "scroll to
    /// bottom" is a plain scroll-position fact and must never depend on
    /// whether there happen to be any user messages to navigate between.
    func testNoUserMessagesAtAllStillOffersScrollToBottomWhenNotNearBottom() {
        let nav = JumpNavigation(sequences: [], topmostVisible: nil, isNearBottom: false)
        XCTAssertFalse(nav.hasPrevious, "no user messages at all -- nothing to go back to")
        XCTAssertTrue(nav.hasNext, "still scrolled away from the bottom -- the bottom arrow must still work")
        XCTAssertNil(nav.nextTarget, "next with no messages at all still means scroll to bottom")
    }

    // MARK: Nothing currently visible (scrolled below the last user message)

    func testNothingVisibleNearBottomHasPreviousOnly() {
        // Scrolled down into trailing assistant/tool content, already at
        // the bottom -- there's somewhere to go back UP to, but nowhere
        // further down.
        let nav = JumpNavigation(sequences: [1, 2, 3], topmostVisible: nil, isNearBottom: true)
        XCTAssertTrue(nav.hasPrevious)
        XCTAssertEqual(nav.previousTarget, 3, "previous from 'below everything' means the newest user message")
        XCTAssertFalse(nav.hasNext, "already at the bottom with nothing above visible -- nowhere further to go")
    }

    func testNothingVisibleNotNearBottomHasBothDirections() {
        // Scrolled below the last user message, but into a long reply that
        // hasn't reached the true bottom yet -- both directions are useful.
        let nav = JumpNavigation(sequences: [1, 2, 3], topmostVisible: nil, isNearBottom: false)
        XCTAssertTrue(nav.hasPrevious)
        XCTAssertTrue(nav.hasNext)
        XCTAssertNil(nav.nextTarget, "next with nothing visible means scroll to bottom, not a specific message")
    }

    // MARK: Boundary: first user message visible

    func testOnFirstMessageHasNextOnlyNotPrevious() {
        let nav = JumpNavigation(sequences: [1, 2, 3], topmostVisible: 1, isNearBottom: false)
        XCTAssertFalse(nav.hasPrevious, "already on the oldest user message -- nothing earlier")
        XCTAssertTrue(nav.hasNext)
        XCTAssertEqual(nav.nextTarget, 2)
    }

    /// `previousTarget`'s documented behavior when there IS no previous:
    /// falls back to `.last`, matching "nothing visible" -- exercised here
    /// so a future change can't silently start returning something else
    /// (e.g. nil) when hasPrevious is already false and this is never
    /// actually called for jumping, but is a real value other code could
    /// read.
    func testPreviousTargetOnFirstMessageFallsBackToLast() {
        let nav = JumpNavigation(sequences: [1, 2, 3], topmostVisible: 1, isNearBottom: false)
        XCTAssertEqual(nav.previousTarget, 3)
    }

    // MARK: Boundary: last user message visible

    func testOnLastMessageNearBottomHasNeitherDirection() {
        let nav = JumpNavigation(sequences: [1, 2, 3], topmostVisible: 3, isNearBottom: true)
        XCTAssertTrue(nav.hasPrevious)
        XCTAssertFalse(nav.hasNext, "on the newest message AND already at the bottom -- truly nowhere to go down")
    }

    func testOnLastMessageNotNearBottomStillHasNext() {
        // On the newest user message, but a long reply below it hasn't
        // scrolled into view yet -- "next" should still offer a way down
        // to the true bottom, not disappear just because there's no LATER
        // user message.
        let nav = JumpNavigation(sequences: [1, 2, 3], topmostVisible: 3, isNearBottom: false)
        XCTAssertTrue(nav.hasNext)
        XCTAssertNil(nav.nextTarget, "no later user message exists, so next means scroll to bottom")
    }

    // MARK: Middle position

    func testMiddleMessageHasBothDirectionsToAdjacentTargets() {
        let nav = JumpNavigation(sequences: [10, 20, 30, 40], topmostVisible: 20, isNearBottom: false)
        XCTAssertTrue(nav.hasPrevious)
        XCTAssertEqual(nav.previousTarget, 10)
        XCTAssertTrue(nav.hasNext)
        XCTAssertEqual(nav.nextTarget, 30)
    }

    // MARK: Single message

    func testSingleMessageVisibleHasNeitherDirectionWhenNearBottom() {
        let nav = JumpNavigation(sequences: [5], topmostVisible: 5, isNearBottom: true)
        XCTAssertFalse(nav.hasPrevious)
        XCTAssertFalse(nav.hasNext)
    }

    // MARK: Stale / unknown topmostVisible

    /// If `topmostVisible` names a sequence that isn't actually in
    /// `sequences` (e.g. a stale value from a message list that has since
    /// reloaded), the lookup must fail safely to "nothing visible"
    /// behavior, not crash or misbehave.
    func testUnknownTopmostVisibleFallsBackToNothingVisibleBehavior() {
        let nav = JumpNavigation(sequences: [1, 2, 3], topmostVisible: 999, isNearBottom: true)
        XCTAssertTrue(nav.hasPrevious)
        XCTAssertEqual(nav.previousTarget, 3)
        XCTAssertFalse(nav.hasNext)
    }
}
