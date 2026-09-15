import XCTest
@testable import Barry

/// `Tests/Fixtures/tool-run-kpd-real.json` is a REAL message stream shape
/// captured from the live local Barry API, session `kPdNYibZbAuePBEEWtFEZ`
/// -- the same session the approved mockup cites for its "100 consecutive
/// Bash calls" worked example. Only `type`/`sequence`/`role`/`name` were
/// kept when the fixture was captured (everything else -- `input`,
/// `result`, `content` -- was dropped entirely before writing the file), so
/// there is no way for real command text, tool output, or credentials to
/// have ended up in it; a grep for sk-/Bearer/AKIA/key=/barry_-style tokens
/// over the fixture at capture time also came back empty. Grouping only
/// ever reads `type`/`name`/`sequence`, so this skeleton exercises the real
/// logic identically to the full payload.
final class MessageGroupingTests: XCTestCase {

    /// Decodes directly as `[Message]` under a `{"messages": [...]}`
    /// wrapper key -- NOT `MessagesPage`, which also requires `hasMore`
    /// (non-optional) that this trimmed fixture deliberately omits, along
    /// with everything else `MessageGrouping` doesn't read.
    private struct FixtureWrapper: Decodable { let messages: [Message] }

    private func loadFixtureMessages() -> [Message] {
        let thisFile = URL(fileURLWithPath: #filePath)
        let url = thisFile.deletingLastPathComponent().appendingPathComponent("Fixtures/tool-run-kpd-real.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode(FixtureWrapper.self, from: data).messages
        } catch {
            XCTFail("fixture failed to decode: \(error)")
            return []
        }
    }

    // MARK: Real captured data

    /// The real session has runs of many lengths in one 362-message window:
    /// 48, 30, 15, 14, 12 (x2), 8, 7, 6, 4 (all >= 3, must group) and
    /// several of 1-2 (must NOT group) -- a strong natural boundary-value
    /// spread without having to synthesize it.
    func testGroupsRealSessionWithMixedRunLengths() {
        let messages = loadFixtureMessages()
        XCTAssertEqual(messages.count, 362, "fixture must be present and complete")

        let items = MessageGrouping.group(messages)

        let groups = items.compactMap { item -> ToolRun? in
            if case .group(let run) = item { return run }
            return nil
        }
        let counts = groups.map(\.count).sorted(by: >)

        // Every one of these real run lengths must have collapsed.
        for expected in [48, 30, 15, 14, 12, 12, 8, 7, 6, 4] {
            XCTAssertTrue(counts.contains(expected), "expected a real \(expected)-call run to be grouped; got run lengths \(counts)")
        }
        // Every grouped run is same-tool-name and long enough.
        for run in groups {
            XCTAssertGreaterThanOrEqual(run.count, MessageGrouping.minimumRunLength)
            XCTAssertTrue(run.messages.allSatisfy { $0.name == run.toolName })
        }

        // Flattening every item's message(s) back out must reconstruct the
        // original stream exactly, in order -- grouping must never drop,
        // duplicate, or reorder a message.
        let flattened = items.flatMap { item -> [Message] in
            switch item {
            case .single(let m): return [m]
            case .group(let run): return run.messages
            }
        }
        XCTAssertEqual(flattened.map(\.sequence), messages.map(\.sequence))
    }

    /// Runs of 1-2 in the real data must pass through as individual
    /// `.single` items, not tiny one-off groups.
    func testShortRunsInRealDataStayUngrouped() {
        let messages = loadFixtureMessages()
        let items = MessageGrouping.group(messages)
        let groupedSequences = Set(items.compactMap { item -> [Int]? in
            if case .group(let run) = item { return run.messages.map(\.sequence) }
            return nil
        }.flatMap { $0 })

        // A message that is a Bash call but adjacent to a differently-named
        // tool or text on both sides (a genuine isolated call in the real
        // data) must appear as `.single`, not swallowed into some group.
        var isolatedToolSequences: [Int] = []
        for (i, m) in messages.enumerated() where m.isTool {
            let prevSameName = i > 0 && messages[i - 1].isTool && messages[i - 1].name == m.name
            let nextSameName = i < messages.count - 1 && messages[i + 1].isTool && messages[i + 1].name == m.name
            if !prevSameName && !nextSameName {
                isolatedToolSequences.append(m.sequence)
            }
        }
        XCTAssertFalse(isolatedToolSequences.isEmpty, "fixture should contain at least one isolated tool call to test")
        for seq in isolatedToolSequences {
            XCTAssertFalse(groupedSequences.contains(seq), "sequence \(seq) is an isolated tool call and must not be inside a group")
        }
    }

    // MARK: Boundary values on `minimumRunLength`

    func testRunOfTwoStaysUngrouped() {
        let messages = toolMessages(name: "Read", count: 2)
        let items = MessageGrouping.group(messages)
        XCTAssertEqual(items.count, 2)
        for item in items {
            if case .single = item {} else { XCTFail("a run of 2 must not group") }
        }
    }

    func testRunOfExactlyThreeGroups() {
        let messages = toolMessages(name: "Read", count: 3)
        let items = MessageGrouping.group(messages)
        XCTAssertEqual(items.count, 1)
        guard case .group(let run) = items[0] else { return XCTFail("a run of exactly 3 (the threshold) must group") }
        XCTAssertEqual(run.count, 3)
        XCTAssertEqual(run.toolName, "Read")
    }

    func testRunOfFourGroups() {
        let messages = toolMessages(name: "Read", count: 4)
        let items = MessageGrouping.group(messages)
        XCTAssertEqual(items.count, 1)
        guard case .group(let run) = items[0] else { return XCTFail("a run above the threshold must group") }
        XCTAssertEqual(run.count, 4)
    }

    // MARK: Grouping rule: consecutive AND same tool name

    func testDifferentToolNamesBreakTheRun() {
        // Bash, Bash, Bash, Read, Read, Read -- two separate runs of 3, not one run of 6.
        let messages = toolMessages(name: "Bash", count: 3) + toolMessages(name: "Read", count: 3, startSequence: 3)
        let items = MessageGrouping.group(messages)
        XCTAssertEqual(items.count, 2)
        guard case .group(let first) = items[0], case .group(let second) = items[1] else {
            return XCTFail("expected two separate groups")
        }
        XCTAssertEqual(first.toolName, "Bash")
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(second.toolName, "Read")
        XCTAssertEqual(second.count, 3)
    }

    func testAssistantTextBreaksTheRun() {
        // Bash x3, assistant text, Bash x3 -- two groups either side of the text, not one run of 6.
        var messages = toolMessages(name: "Bash", count: 3)
        messages.append(textMessage(role: "assistant", sequence: 3))
        messages.append(contentsOf: toolMessages(name: "Bash", count: 3, startSequence: 4))

        let items = MessageGrouping.group(messages)
        XCTAssertEqual(items.count, 3, "expected group, single text, group")
        guard case .group(let first) = items[0] else { return XCTFail("expected first item to be a group") }
        guard case .single(let text) = items[1] else { return XCTFail("expected middle item to be the single text message") }
        guard case .group(let second) = items[2] else { return XCTFail("expected third item to be a group") }
        XCTAssertEqual(first.count, 3)
        XCTAssertTrue(text.isAssistant)
        XCTAssertEqual(second.count, 3)
    }

    func testIsolatedToolCallsInterleavedWithTextAllStaySingle() {
        // A realistic short exchange: text, tool, text, tool, text -- nothing should ever group.
        let messages = [
            textMessage(role: "user", sequence: 0),
            toolMessage(name: "Bash", sequence: 1),
            textMessage(role: "assistant", sequence: 2),
            toolMessage(name: "Read", sequence: 3),
            textMessage(role: "assistant", sequence: 4),
        ]
        let items = MessageGrouping.group(messages)
        XCTAssertEqual(items.count, 5)
        for item in items {
            if case .group = item { XCTFail("nothing here should group") }
        }
    }

    func testEmptyMessageListProducesEmptyResult() {
        XCTAssertTrue(MessageGrouping.group([]).isEmpty)
    }

    // MARK: - Fixture builders

    private func toolMessage(name: String, sequence: Int) -> Message {
        let json = """
        {"type":"tool_start","name":"\(name)","sequence":\(sequence)}
        """
        return try! JSONDecoder().decode(Message.self, from: Data(json.utf8))
    }

    private func toolMessages(name: String, count: Int, startSequence: Int = 0) -> [Message] {
        (0..<count).map { toolMessage(name: name, sequence: startSequence + $0) }
    }

    private func textMessage(role: String, sequence: Int) -> Message {
        let json = """
        {"type":"text","role":"\(role)","content":"hello","sequence":\(sequence)}
        """
        return try! JSONDecoder().decode(Message.self, from: Data(json.utf8))
    }
}
