import Foundation

/// Whether a user message should start collapsed, and where to cut it if
/// so -- pure logic (no view dependency), matching this app's established
/// pattern (`MessageGrouping`, `JumpNavigation`) of keeping the boundary
/// conditions unit-testable without SwiftUI's view lifecycle in the way.
enum MessageCollapse {
    /// Character count past which a message is long enough to collapse.
    /// Chosen from the approved mockup's own worked example (a real
    /// four-sentence multi-ask message, ~340 characters) landing clearly
    /// past this line, while a short question or quick reply -- the
    /// overwhelming majority of real messages -- stays well under it.
    static let characterThreshold = 240

    /// Line count past which a message collapses even if short in total
    /// characters -- a message that's mostly short lines (a pasted list, a
    /// stack trace) can clear many lines without ever reaching the
    /// character threshold.
    static let lineThreshold = 4

    /// True if `text` is long enough that it should render collapsed by
    /// default (with a "Show more" affordance), by either measure.
    static func shouldCollapse(_ text: String) -> Bool {
        text.count > characterThreshold || lineCount(of: text) > lineThreshold
    }

    /// Counts newline-separated lines the same way SwiftUI's own line
    /// breaking would split on explicit `\n`s -- not a wrapped-line
    /// estimate (that depends on the rendered width/font, which this pure
    /// function has no access to and shouldn't need).
    static func lineCount(of text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}
