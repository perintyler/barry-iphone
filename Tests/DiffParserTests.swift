import XCTest
@testable import Barry

/// Fixtures in `Tests/Fixtures/*.diff` are REAL diff text captured from the
/// live local Barry API (see DiffParserTests provenance comment below) —
/// not synthetic examples. Threshold tests use constructed inputs at exact
/// boundary values to prove the numbers ported from ChangesView.svelte are
/// actually implemented, not just documented in a comment.
final class DiffParserTests: XCTestCase {

    /// Fixtures live next to this test file on disk; loaded by real file
    /// path rather than through the app bundle so the test doesn't depend
    /// on xcodegen's resource-copy behavior for the `Tests` target.
    private func loadFixture(_ name: String) -> String {
        let thisFile = URL(fileURLWithPath: #filePath)
        let url = thisFile.deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: Real captured diffs

    /// Captured 2026-09-15 from `GET /api/v1/sessions/YeXAll8IzvLm5j2MudmOI/diff?mode=uncommitted`
    /// against session YeXAll8IzvLm5j2MudmOI (repo /Users/tyler/vantage/core):
    /// 4 files -- 3 real, unmodified source edits (a .vue component, its
    /// spec, a Ruby test) plus one untracked file whose hunk carries 5,846 real content lines (the
    /// server's untracked-file-as-synthesized-new-file-diff behavior noted
    /// in the task brief). The untracked file's 5,846 lines were replaced
    /// with synthetic placeholder text before this fixture was committed --
    /// the real file was a session transcript that turned out to contain
    /// pasted API keys (caught by GitHub's push protection on the first
    /// push attempt). Only that one file's body is synthetic; its diff
    /// SHAPE (new-file marker, line count, /dev/null oldName) is preserved
    /// exactly, and the other 3 files are byte-for-byte the real captured
    /// diff. 383,787 bytes raw.
    func testParsesRealUncommittedDiff() {
        let raw = loadFixture("uncommitted-real.diff")
        XCTAssertFalse(raw.isEmpty, "fixture must be present and non-empty")

        let files = DiffParser.parse(raw)
        XCTAssertEqual(files.count, 4)

        let names = files.map(\.displayName)
        XCTAssertTrue(names.contains("app/javascript/vue/pages/financial_planning/budgets/StandardBudgetSettingsDialog.vue"))
        XCTAssertTrue(names.contains("app/javascript/vue/pages/financial_planning/budgets/__tests__/StandardBudgetSettingsDialog.spec.ts"))
        XCTAssertTrue(names.contains("test/forms/budget_form_test.rb"))
        XCTAssertTrue(names.contains("2026-09-09-201923-read-httpsappnotioncompvantageshopenroute.txt"))

        // The untracked file is synthesized server-side as `git diff
        // --no-index /dev/null <file>` -- oldName is /dev/null and every
        // line in it is an addition.
        guard let untracked = files.first(where: { $0.displayName.hasSuffix(".txt") }) else {
            return XCTFail("expected the untracked .txt file to parse")
        }
        XCTAssertTrue(untracked.isNewFile)
        XCTAssertEqual(untracked.oldName, "/dev/null")
        XCTAssertEqual(untracked.deletions, 0)
        XCTAssertEqual(untracked.additions, 5846)
        // totalLines is 5847, one more than additions: parseDiff's final
        // line of the raw diff text is "" (the artifact of splitting a
        // trailing-newline-terminated string on "\n"), which falls into
        // the `line === ''` branch of the ORIGINAL svelte parser exactly
        // as ported here, and is pushed as one spurious trailing ctx line.
        // This is a real, pre-existing quirk of the ported algorithm, not
        // a fidelity bug in this port -- verified against
        // bags/barry.works/src/lib/components/ChangesView.svelte's own
        // `else if (firstChar === ' ' || line === '')` branch, which has
        // the identical behavior for the identical reason.
        XCTAssertEqual(untracked.totalLines, 5847)

        // Real edits parse real add/del counts (not zero, not swapped).
        guard let vueFile = files.first(where: { $0.displayName.hasSuffix(".vue") }) else {
            return XCTFail("expected the .vue file to parse")
        }
        XCTAssertGreaterThan(vueFile.additions, 0)
        XCTAssertFalse(vueFile.isNewFile)
        XCTAssertFalse(vueFile.hunks.isEmpty)

        // annotateHunks assigned real line numbers, not the zero default.
        for hunk in vueFile.hunks {
            for line in hunk.lines {
                XCTAssertGreaterThan(line.lineNum, 0, "every parsed line should get a real line number")
            }
        }

        // This fixture alone exceeds the 100KB auto-collapse threshold.
        XCTAssertGreaterThan(raw.utf8.count, 100_000)
        XCTAssertTrue(DiffThresholds.shouldAutoCollapse(diffSizeBytes: raw.utf8.count, files: files))
    }

    /// Captured 2026-09-15 from `GET /api/v1/sessions/DNfLwhyh7iMUH4Bra6Lug/diff?mode=branch`
    /// (repo /Users/tyler/repos/bags): 19 files -- a real README.md content
    /// edit plus 18 submodule-pointer diffs (`-Subproject commit X` /
    /// `+Subproject commit Y`, one hunk each). Exercises the file-count
    /// threshold (19 > 15) and many-small-single-hunk-files parsing.
    func testParsesRealBranchDiff() {
        let raw = loadFixture("branch-real.diff")
        XCTAssertFalse(raw.isEmpty, "fixture must be present and non-empty")

        let files = DiffParser.parse(raw)
        XCTAssertEqual(files.count, 19)
        XCTAssertGreaterThan(files.count, 15, "fixture should exceed the file-count auto-collapse threshold")

        guard let readme = files.first(where: { $0.displayName == "README.md" }) else {
            return XCTFail("expected README.md to parse")
        }
        XCTAssertGreaterThan(readme.deletions, 0)
        XCTAssertGreaterThan(readme.additions, 0)

        guard let submodule = files.first(where: { $0.displayName == "ableton" }) else {
            return XCTFail("expected the 'ableton' submodule pointer diff to parse")
        }
        XCTAssertEqual(submodule.hunks.count, 1)
        XCTAssertEqual(submodule.additions, 1)
        XCTAssertEqual(submodule.deletions, 1)
        XCTAssertTrue(submodule.hunks[0].lines.contains { $0.content.hasPrefix("Subproject commit") })

        XCTAssertTrue(DiffThresholds.shouldAutoCollapse(diffSizeBytes: raw.utf8.count, files: files),
                      "19 files alone should trip auto-collapse regardless of byte size")
    }

    func testEmptyDiffParsesToNoFiles() {
        XCTAssertTrue(DiffParser.parse("").isEmpty)
        XCTAssertTrue(DiffParser.parse("   \n  \n").isEmpty)
    }

    // MARK: Synthetic edge cases (renames, binary, new/deleted files)

    func testParsesNewFile() {
        let diff = """
        diff --git a/new.txt b/new.txt
        new file mode 100644
        index 0000000..e69de29
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1,2 @@
        +line one
        +line two
        """
        let files = DiffParser.parse(diff)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isNewFile)
        XCTAssertEqual(files[0].displayName, "new.txt")
        XCTAssertEqual(files[0].additions, 2)
        XCTAssertEqual(files[0].deletions, 0)
    }

    func testParsesDeletedFile() {
        let diff = """
        diff --git a/gone.txt b/gone.txt
        deleted file mode 100644
        index e69de29..0000000
        --- a/gone.txt
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -line one
        -line two
        """
        let files = DiffParser.parse(diff)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isDeletedFile)
        XCTAssertEqual(files[0].displayName, "gone.txt")
        XCTAssertEqual(files[0].deletions, 2)
        XCTAssertEqual(files[0].additions, 0)
    }

    func testParsesRename() {
        let diff = """
        diff --git a/old-name.txt b/new-name.txt
        similarity index 100%
        rename from old-name.txt
        rename to new-name.txt
        """
        let files = DiffParser.parse(diff)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].displayName, "new-name.txt")
        XCTAssertTrue(files[0].hunks.isEmpty, "a pure rename with no content change has no hunks")
    }

    func testFlagsBinaryFile() {
        let diff = """
        diff --git a/image.png b/image.png
        index abc123..def456 100644
        Binary files a/image.png and b/image.png differ
        """
        let files = DiffParser.parse(diff)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isBinary)
        XCTAssertEqual(files[0].displayName, "image.png")
    }

    func testAnnotatesHunkLineNumbers() {
        let diff = """
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -10,3 +10,4 @@ some context
         unchanged
        -removed line
        +added line
        +another added line
         trailing unchanged
        """
        let files = DiffParser.parse(diff)
        XCTAssertEqual(files.count, 1)
        let lines = files[0].hunks[0].lines
        // ctx "unchanged" -> new line 10
        XCTAssertEqual(lines[0].type, .ctx)
        XCTAssertEqual(lines[0].lineNum, 10)
        // del "removed line" -> old line 11 (ctx already advanced old to 11)
        XCTAssertEqual(lines[1].type, .del)
        XCTAssertEqual(lines[1].lineNum, 11)
        // add "added line" -> new line 11 (ctx already advanced new to 11)
        XCTAssertEqual(lines[2].type, .add)
        XCTAssertEqual(lines[2].lineNum, 11)
        // add "another added line" -> new line 12
        XCTAssertEqual(lines[3].type, .add)
        XCTAssertEqual(lines[3].lineNum, 12)
        // ctx "trailing unchanged" -> new line 13
        XCTAssertEqual(lines[4].type, .ctx)
        XCTAssertEqual(lines[4].lineNum, 13)
    }

    func testHunkHeaderContextCaptured() {
        let diff = """
        diff --git a/f.swift b/f.swift
        --- a/f.swift
        +++ b/f.swift
        @@ -5,2 +5,2 @@ func foo() {
        -old
        +new
        """
        let files = DiffParser.parse(diff)
        XCTAssertEqual(files[0].hunks[0].context, " func foo() {")
        XCTAssertEqual(files[0].hunks[0].oldStart, 5)
        XCTAssertEqual(files[0].hunks[0].newStart, 5)
    }
}

/// Threshold tests: constructed inputs at EXACT boundary values, proving
/// the numbers ported from `applySmartFileCollapse()` / the render gating
/// in ChangesView.svelte are really implemented as `>`/`>=` where the
/// source says so -- not approximated.
final class DiffThresholdTests: XCTestCase {

    private func makeFile(lines: Int, additions: Int, deletions: Int) -> DiffFile {
        var content: [DiffLine] = []
        for i in 0..<additions { content.append(DiffLine(type: .add, content: "a\(i)", lineNum: i)) }
        for i in 0..<deletions { content.append(DiffLine(type: .del, content: "d\(i)", lineNum: i)) }
        while content.count < lines { content.append(DiffLine(type: .ctx, content: "c", lineNum: 0)) }
        let hunk = DiffHunk(header: "@@ -1,1 +1,1 @@", oldStart: 1, newStart: 1, context: "", lines: content)
        return DiffFile(oldName: "a", newName: "a", hunks: [hunk], additions: additions, deletions: deletions, isBinary: false)
    }

    // MARK: shouldAutoCollapse: diffSize > 100_000

    func testAutoCollapseSizeThresholdAt100000IsFalse() {
        let files = [makeFile(lines: 5, additions: 1, deletions: 1)]
        XCTAssertFalse(DiffThresholds.shouldAutoCollapse(diffSizeBytes: 100_000, files: files),
                       "boundary value itself must NOT trigger -- svelte source uses strict >")
    }

    func testAutoCollapseSizeThresholdAt100001IsTrue() {
        let files = [makeFile(lines: 5, additions: 1, deletions: 1)]
        XCTAssertTrue(DiffThresholds.shouldAutoCollapse(diffSizeBytes: 100_001, files: files))
    }

    // MARK: shouldAutoCollapse: files.length > 15

    func testAutoCollapseFileCountAt15IsFalse() {
        let files = (0..<15).map { _ in makeFile(lines: 5, additions: 1, deletions: 1) }
        XCTAssertFalse(DiffThresholds.shouldAutoCollapse(diffSizeBytes: 0, files: files),
                       "exactly 15 files must NOT trigger -- strict >")
    }

    func testAutoCollapseFileCountAt16IsTrue() {
        let files = (0..<16).map { _ in makeFile(lines: 5, additions: 1, deletions: 1) }
        XCTAssertTrue(DiffThresholds.shouldAutoCollapse(diffSizeBytes: 0, files: files))
    }

    // MARK: shouldAutoCollapse: totalLines > 1000

    func testAutoCollapseTotalLinesAt1000IsFalse() {
        // One file with exactly 1000 total lines across all its hunks.
        let files = [makeFile(lines: 1000, additions: 500, deletions: 0)]
        XCTAssertFalse(DiffThresholds.shouldAutoCollapse(diffSizeBytes: 0, files: files),
                       "exactly 1000 total lines must NOT trigger -- strict >")
    }

    func testAutoCollapseTotalLinesAt1001IsTrue() {
        let files = [makeFile(lines: 1001, additions: 500, deletions: 0)]
        XCTAssertTrue(DiffThresholds.shouldAutoCollapse(diffSizeBytes: 0, files: files))
    }

    // MARK: keepExpandedByDefault: fileLines < 20

    func testKeepExpandedAt19LinesIsTrue() {
        let file = makeFile(lines: 19, additions: 0, deletions: 0)
        XCTAssertTrue(DiffThresholds.keepExpandedByDefault(file: file, index: 99))
    }

    func testKeepExpandedAt20LinesIsFalse() {
        // 20 lines, >= 10 changes, index far past the "first 2" exception.
        let file = makeFile(lines: 20, additions: 10, deletions: 0)
        XCTAssertFalse(DiffThresholds.keepExpandedByDefault(file: file, index: 99),
                       "exactly 20 lines must NOT qualify for the <20 exception -- strict <")
    }

    // MARK: keepExpandedByDefault: fileChanges < 10

    func testKeepExpandedAt9ChangesIsTrue() {
        let file = makeFile(lines: 50, additions: 9, deletions: 0)
        XCTAssertTrue(DiffThresholds.keepExpandedByDefault(file: file, index: 99))
    }

    func testKeepExpandedAt10ChangesIsFalse() {
        let file = makeFile(lines: 50, additions: 10, deletions: 0)
        XCTAssertFalse(DiffThresholds.keepExpandedByDefault(file: file, index: 99),
                       "exactly 10 changes must NOT qualify for the <10 exception -- strict <")
    }

    // MARK: keepExpandedByDefault: idx < 2 (first 2 files)

    func testKeepExpandedAtIndex1IsTrue() {
        let file = makeFile(lines: 500, additions: 500, deletions: 0)
        XCTAssertTrue(DiffThresholds.keepExpandedByDefault(file: file, index: 1))
    }

    func testKeepExpandedAtIndex2IsFalse() {
        let file = makeFile(lines: 500, additions: 500, deletions: 0)
        XCTAssertFalse(DiffThresholds.keepExpandedByDefault(file: file, index: 2),
                       "the third file (index 2) is past the 'first 2 files' exception")
    }

    // MARK: isPerformanceMode: diffSize > 1_000_000

    func testPerformanceModeAt1000000IsFalse() {
        XCTAssertFalse(DiffThresholds.isPerformanceMode(diffSizeBytes: 1_000_000),
                       "exactly 1MB must NOT trigger -- strict >")
    }

    func testPerformanceModeAt1000001IsTrue() {
        XCTAssertTrue(DiffThresholds.isPerformanceMode(diffSizeBytes: 1_000_001))
    }

    // MARK: isLargeFile: fileLines > 200

    func testIsLargeFileAt200LinesIsFalse() {
        let file = makeFile(lines: 200, additions: 200, deletions: 0)
        XCTAssertFalse(DiffThresholds.isLargeFile(file), "exactly 200 lines must NOT count as large -- strict >")
    }

    func testIsLargeFileAt201LinesIsTrue() {
        let file = makeFile(lines: 201, additions: 201, deletions: 0)
        XCTAssertTrue(DiffThresholds.isLargeFile(file))
    }

    // MARK: hunk paging: default 3, +5 per click, capped at hunks.count

    func testDefaultHunksToShowCapsAt3ForLargeFile() {
        var hunks: [DiffHunk] = []
        for i in 0..<10 {
            hunks.append(DiffHunk(header: "@@ h\(i) @@", oldStart: 1, newStart: 1, context: "",
                                   lines: (0..<25).map { DiffLine(type: .ctx, content: "l\($0)", lineNum: $0) }))
        }
        let file = DiffFile(oldName: "a", newName: "a", hunks: hunks, additions: 0, deletions: 0, isBinary: false)
        XCTAssertEqual(file.totalLines, 250)
        XCTAssertTrue(DiffThresholds.isLargeFile(file))
        XCTAssertEqual(DiffThresholds.defaultHunksToShow(for: file), 3)
    }

    func testDefaultHunksToShowIsAllHunksForNonLargeFile() {
        var hunks: [DiffHunk] = []
        for i in 0..<10 {
            hunks.append(DiffHunk(header: "@@ h\(i) @@", oldStart: 1, newStart: 1, context: "",
                                   lines: (0..<5).map { DiffLine(type: .ctx, content: "l\($0)", lineNum: $0) }))
        }
        let file = DiffFile(oldName: "a", newName: "a", hunks: hunks, additions: 0, deletions: 0, isBinary: false)
        XCTAssertEqual(file.totalLines, 50)
        XCTAssertFalse(DiffThresholds.isLargeFile(file))
        XCTAssertEqual(DiffThresholds.defaultHunksToShow(for: file), 10, "small file shows all hunks immediately")
    }

    func testNextHunksToShowAdvancesByFiveAndCaps() {
        var hunks: [DiffHunk] = []
        for i in 0..<10 {
            hunks.append(DiffHunk(header: "@@ h\(i) @@", oldStart: 1, newStart: 1, context: "", lines: []))
        }
        let file = DiffFile(oldName: "a", newName: "a", hunks: hunks, additions: 0, deletions: 0, isBinary: false)
        XCTAssertEqual(DiffThresholds.nextHunksToShow(current: 3, file: file), 8)
        XCTAssertEqual(DiffThresholds.nextHunksToShow(current: 8, file: file), 10, "caps at the real hunk count")
    }
}
