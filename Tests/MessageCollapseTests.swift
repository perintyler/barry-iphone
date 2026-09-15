import XCTest
@testable import Barry

final class MessageCollapseTests: XCTestCase {

    // MARK: Character threshold boundary

    func testExactlyAtCharacterThresholdDoesNotCollapse() {
        let text = String(repeating: "a", count: MessageCollapse.characterThreshold)
        XCTAssertFalse(MessageCollapse.shouldCollapse(text))
    }

    func testOneOverCharacterThresholdCollapses() {
        let text = String(repeating: "a", count: MessageCollapse.characterThreshold + 1)
        XCTAssertTrue(MessageCollapse.shouldCollapse(text))
    }

    // MARK: Line threshold boundary

    func testExactlyAtLineThresholdDoesNotCollapse() {
        let text = Array(repeating: "line", count: MessageCollapse.lineThreshold).joined(separator: "\n")
        XCTAssertEqual(MessageCollapse.lineCount(of: text), MessageCollapse.lineThreshold)
        XCTAssertFalse(MessageCollapse.shouldCollapse(text))
    }

    func testOneOverLineThresholdCollapsesEvenIfShort() {
        // Short total characters, but more lines than the threshold -- a
        // pasted list or short stack trace shape.
        let text = Array(repeating: "x", count: MessageCollapse.lineThreshold + 1).joined(separator: "\n")
        XCTAssertLessThan(text.count, MessageCollapse.characterThreshold, "this case must trigger via LINE count, not character count")
        XCTAssertTrue(MessageCollapse.shouldCollapse(text))
    }

    // MARK: Real-world shapes

    func testShortQuestionNeverCollapses() {
        XCTAssertFalse(MessageCollapse.shouldCollapse("what did we land tonight?"))
    }

    func testEmptyStringNeverCollapses() {
        XCTAssertFalse(MessageCollapse.shouldCollapse(""))
        XCTAssertEqual(MessageCollapse.lineCount(of: ""), 0)
    }

    /// The real multi-ask message from this session that motivated the
    /// feature -- measured, not assumed: at 141 real characters, it's
    /// actually a good example of a message that stays SHORT of the
    /// threshold despite covering four distinct asks in one message, which
    /// is exactly the "short questions/requests are never touched" case
    /// this feature is careful not to over-trigger on.
    func testRealMultiAskMessageStaysUnderThresholdDespiteFourAsks() {
        let text = "i'd like git diffs to be syntax highlighted. i'd like to use better icons. i'd like user messages to be collapsable and have more elegant ux."
        XCTAssertEqual(text.count, 141)
        XCTAssertFalse(MessageCollapse.shouldCollapse(text))
    }

    /// A genuinely long real example: an assistant explanation from this
    /// same session (commit 0a55a3b's own commit message body, a realistic
    /// stand-in for "the kind of long multi-paragraph content a user might
    /// paste into the input" -- pasted error logs and long prompts are the
    /// real trigger case, not typed multi-sentence requests).
    func testLongPastedContentCollapses() {
        let text = """
        AssistantText used SwiftUI's Text(markdown:) with .inlineOnlyPreservingWhitespace, which parses inline emphasis only -- fenced code blocks, tables, and lists all printed as literal characters. Swaps in swift-markdown-ui, themed via Theme.barry to match the app's existing card/color language, with a per-message parse cache so scrolling past an already-rendered message never re-parses it.
        """
        XCTAssertGreaterThan(text.count, MessageCollapse.characterThreshold)
        XCTAssertTrue(MessageCollapse.shouldCollapse(text))
    }
}
