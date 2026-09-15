import XCTest
@testable import Barry

/// Fixtures in `Tests/Fixtures/bookkeeping-*.txt` are REAL `session.summary`
/// text captured from the live local Barry API -- not synthetic examples.
/// Screened for credential-looking content before being committed (see the
/// task brief / QA.md discipline established by DiffParserTests); both
/// fixtures contain only file paths, commit hashes, and prose, no secrets.
final class BookkeepingParserTests: XCTestCase {

    private func loadFixture(_ name: String) -> String {
        let thisFile = URL(fileURLWithPath: #filePath)
        let url = thisFile.deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: Real captured summaries

    /// Captured 2026-09-15 from session `kPdNYibZbAuePBEEWtFEZ`
    /// ("trait-picker-mockup-comparison") -- this is the exact session the
    /// approved mockup itself cites as its real bookkeeping example. 9
    /// entries, 1 topic-change drift, and a real instance of the
    /// "header present, body empty" case the omit-when-empty rule allows
    /// for (the 2026-09-14 22:19 entry has `### Done` and `### Learnings`
    /// headers with nothing under them).
    func testParsesRealKpdSummary() throws {
        let raw = loadFixture("bookkeeping-kpd-real.txt")
        XCTAssertFalse(raw.isEmpty, "fixture must be present and non-empty")

        let entries = BookkeepingParser.parse(raw)
        XCTAssertEqual(entries.count, 9)

        let driftEntries = entries.filter(\.isDrift)
        XCTAssertEqual(driftEntries.count, 1)
        let drift = try XCTUnwrap(driftEntries.first)
        XCTAssertEqual(drift.timestampRaw, "2026-09-15 02:36")
        XCTAssertEqual(drift.driftDescription, "Was trait-picker-mockup-comparison; now identities app bundle verification.")
        XCTAssertNotNil(drift.timestamp, "a real ### YYYY-MM-DD HH:MM header must parse to a Date")

        // The 22:19 entry: "### Done" and "### Learnings" headers appear in
        // the raw text with nothing underneath -- must decode as nil
        // sections, not empty-string ones.
        guard let emptyHeaders = entries.first(where: { $0.timestampRaw == "2026-09-14 22:19" }) else {
            return XCTFail("expected the 22:19 entry to parse")
        }
        XCTAssertNil(emptyHeaders.done, "a header with no body text must be nil, not an empty string")
        XCTAssertNil(emptyHeaders.learnings)
        XCTAssertNotNil(emptyHeaders.wentRight, "this entry's 'What went right' section does have real content")
        XCTAssertEqual(emptyHeaders.model, "qwen3:4b")

        // The drift entry's real sections still parse fully alongside the
        // drift metadata.
        XCTAssertNotNil(drift.done)
        XCTAssertTrue(drift.done?.contains("Barry app bundle paths") == true)
        XCTAssertNotNil(drift.learnings)
        XCTAssertNotNil(drift.wentRight)
        XCTAssertNotNil(drift.wentWrong)
        XCTAssertNotNil(drift.openLoops)
        XCTAssertEqual(drift.model, "qwen3:4b")

        // Every entry in this fixture carries the same live model.
        for entry in entries {
            XCTAssertEqual(entry.model, "qwen3:4b")
        }

        // An entry with an explicit "- None" body under a section header is
        // real prose content (the model wrote a bulleted "None") -- not an
        // omitted section, so this must NOT be nil, and the bullet marker
        // is preserved verbatim like any other body content.
        guard let noneEntry = entries.first(where: { $0.timestampRaw == "2026-09-15 01:16" }) else {
            return XCTFail("expected the 01:16 entry to parse")
        }
        XCTAssertEqual(noneEntry.wentWrong, "- None")
        XCTAssertEqual(noneEntry.openLoops, "- None")
    }

    /// Captured 2026-09-15 from session `ekpJsY_bSJnjfsSWtyC0f`
    /// ("agent-scope parser fix") -- the largest real summary sampled: 30
    /// entries, 7 topic-change drifts, ~19.9KB. Stresses multiple
    /// consecutive drifts and confirms the parser doesn't crash or
    /// misattribute sections across entry boundaries on a long real ledger.
    func testParsesRealEkpSummaryWithMultipleDrifts() {
        let raw = loadFixture("bookkeeping-ekp-real.txt")
        XCTAssertFalse(raw.isEmpty, "fixture must be present and non-empty")

        let entries = BookkeepingParser.parse(raw)
        XCTAssertEqual(entries.count, 30)

        let driftEntries = entries.filter(\.isDrift)
        XCTAssertEqual(driftEntries.count, 7)
        for drift in driftEntries {
            XCTAssertNotNil(drift.driftDescription)
            XCTAssertTrue(drift.driftDescription?.hasPrefix("Was ") == true)
        }

        // Every real timestamp header must parse to a Date -- a single
        // failure here would mean the regex/format drifted from the real
        // server output.
        for entry in entries {
            XCTAssertNotNil(entry.timestamp, "entry \(entry.timestampRaw) failed to parse as a Date")
        }

        // Chronological order in the raw text is preserved (oldest first);
        // callers reverse for most-recent-first display.
        for i in entries.indices.dropFirst() {
            guard let prev = entries[i - 1].timestamp, let cur = entries[i].timestamp else { continue }
            XCTAssertLessThanOrEqual(prev, cur, "entries should come back in the raw text's chronological order")
        }
    }

    // MARK: Empty / missing input

    func testNilSummaryParsesToNoEntries() {
        XCTAssertTrue(BookkeepingParser.parse(nil).isEmpty)
    }

    func testEmptySummaryParsesToNoEntries() {
        XCTAssertTrue(BookkeepingParser.parse("").isEmpty)
        XCTAssertTrue(BookkeepingParser.parse("   \n  \n").isEmpty)
    }

    // MARK: Synthetic shape tests

    func testParsesSingleEntryAllSections() throws {
        let raw = """
        ### 2026-01-01 09:00

        ### Done
        - did a thing

        ### Learnings
        - learned a thing

        ### What went right
        - right thing

        ### What went wrong
        - wrong thing

        ### Open loops
        - open thing

        <!-- model: llama3:8b -->
        """
        let entries = BookkeepingParser.parse(raw)
        XCTAssertEqual(entries.count, 1)
        let e = try XCTUnwrap(entries.first)
        XCTAssertFalse(e.isDrift)
        XCTAssertNil(e.driftDescription)
        XCTAssertEqual(e.done, "- did a thing")
        XCTAssertEqual(e.learnings, "- learned a thing")
        XCTAssertEqual(e.wentRight, "- right thing")
        XCTAssertEqual(e.wentWrong, "- wrong thing")
        XCTAssertEqual(e.openLoops, "- open thing")
        XCTAssertEqual(e.model, "llama3:8b")
        XCTAssertTrue(e.hasAnySection)
    }

    /// Sections genuinely omitted entirely (not even a header) -- the
    /// "supposed to" behavior per the task brief, distinct from the
    /// "header present, body empty" case covered by the real kpd fixture.
    func testOmittedSectionsProduceNilNotEmptyString() throws {
        let raw = """
        ### 2026-01-01 09:00

        ### Done
        - only this section exists

        <!-- model: qwen3:4b -->
        """
        let entries = BookkeepingParser.parse(raw)
        XCTAssertEqual(entries.count, 1)
        let e = try XCTUnwrap(entries.first)
        XCTAssertEqual(e.done, "- only this section exists")
        XCTAssertNil(e.learnings)
        XCTAssertNil(e.wentRight)
        XCTAssertNil(e.wentWrong)
        XCTAssertNil(e.openLoops)
        XCTAssertFalse(e.hasAnySection == false, "hasAnySection should be true when at least Done exists")
    }

    /// A section with a header but literally nothing under it (blank line
    /// straight to the next "###") must parse to nil, matching the real
    /// kpd fixture's 22:19 entry behavior on synthetic input too.
    func testHeaderOnlySectionIsNil() throws {
        let raw = """
        ### 2026-01-01 09:00

        ### Done

        ### Learnings
        - something

        <!-- model: qwen3:4b -->
        """
        let entries = BookkeepingParser.parse(raw)
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertNil(entry.done)
        XCTAssertEqual(entry.learnings, "- something")
    }

    func testDriftEntryParsesFlagAndDescription() throws {
        let raw = """
        ### 2026-01-01 10:00 ⚠️ TOPIC CHANGE

        Was foo; now bar.

        ### Done
        - switched topics

        <!-- model: qwen3:4b -->
        """
        let entries = BookkeepingParser.parse(raw)
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertTrue(entry.isDrift)
        XCTAssertEqual(entry.driftDescription, "Was foo; now bar.")
        XCTAssertEqual(entry.done, "- switched topics")
    }

    func testMultipleEntriesParseIndependently() {
        let raw = """
        ### 2026-01-01 09:00

        ### Done
        - first entry work

        <!-- model: qwen3:4b -->

        ### 2026-01-01 09:15

        ### Done
        - second entry work

        <!-- model: qwen3:4b -->
        """
        let entries = BookkeepingParser.parse(raw)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.done, "- first entry work")
        XCTAssertEqual(entries.dropFirst().first?.done, "- second entry work")
    }

    func testMultilineSectionContentPreservesLines() throws {
        let raw = """
        ### 2026-01-01 09:00

        ### Done
        - line one
        - line two
        - line three

        <!-- model: qwen3:4b -->
        """
        let entries = BookkeepingParser.parse(raw)
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.done, "- line one\n- line two\n- line three")
    }

    // MARK: Boundary values / negative-control-relevant cases

    /// A timestamp header that's almost right but missing the required
    /// HH:MM must NOT match -- proves the regex is anchored to the real
    /// format, not a loose prefix match.
    func testMalformedTimestampHeaderDoesNotMatch() {
        let raw = """
        ### 2026-01-01

        ### Done
        - should not be captured as a dated entry
        """
        let entries = BookkeepingParser.parse(raw)
        XCTAssertTrue(entries.isEmpty, "a header missing HH:MM is not a valid entry boundary")
    }

    /// The drift marker must be the emoji+text pair exactly as the server
    /// writes it, not any bracketed warning text.
    func testNonDriftEntryWithWarningWordInBodyIsNotFlaggedDrift() throws {
        let raw = """
        ### 2026-01-01 09:00

        ### What went wrong
        - a warning was logged but nothing changed topic

        <!-- model: qwen3:4b -->
        """
        let entries = BookkeepingParser.parse(raw)
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertFalse(entry.isDrift)
    }
}
