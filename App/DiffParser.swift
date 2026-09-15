import Foundation

// MARK: - Parsed diff model

/// One changed file in a unified diff, with its hunks and computed
/// add/delete counts. Mirrors the shape `parseDiff`/`annotateHunks` build in
/// `bags/barry.works/src/lib/components/ChangesView.svelte` — ported
/// faithfully rather than redesigned, since that parser is the
/// battle-tested one against real Barry session diffs.
struct DiffFile: Identifiable, Equatable {
    var oldName: String
    var newName: String
    var hunks: [DiffHunk]
    var additions: Int
    var deletions: Int
    /// True when this file's diff body was exactly "Binary files ... differ"
    /// — the web app silently drops these; this app renders an explicit row
    /// instead (see DiffView), so the parser must still surface the file.
    var isBinary: Bool

    /// Stable per-file identity for SwiftUI lists. Falls back across
    /// old/new name so a rename or a deleted file (newName == "/dev/null")
    /// still gets a non-empty id.
    var id: String {
        if !newName.isEmpty && newName != "/dev/null" { return newName }
        if !oldName.isEmpty { return oldName }
        return "\(newName)|\(oldName)"
    }

    /// The name to show: prefers the new path, falls back to old (deleted
    /// files have newName == "/dev/null"). Matches `displayName()` in the
    /// svelte source exactly.
    var displayName: String {
        if !newName.isEmpty && newName != "/dev/null" { return newName }
        return oldName.isEmpty ? "(unknown)" : oldName
    }

    var isNewFile: Bool { oldName == "/dev/null" }
    var isDeletedFile: Bool { newName == "/dev/null" }

    /// Total line count across all hunks — the input to both the
    /// "keep expanded" exception (< 20 lines) and the per-file
    /// "isLargeFile" hunk-paging threshold (> 200 lines).
    var totalLines: Int { hunks.reduce(0) { $0 + $1.lines.count } }

    var totalChanges: Int { additions + deletions }
}

/// One `@@ -oldStart,oldLines +newStart,newLines @@ context` block.
struct DiffHunk: Identifiable, Equatable {
    var header: String
    var oldStart: Int
    var newStart: Int
    var context: String
    var lines: [DiffLine]

    var id: String { header }
}

/// One line within a hunk. `lineNum` is filled in by `annotateHunks` —
/// the NEW-file line number for add/context lines, the OLD-file line
/// number for delete lines (exactly `annotateHunks` in the svelte source).
struct DiffLine: Identifiable, Equatable {
    enum Kind: Equatable { case add, del, ctx }

    var type: Kind
    var content: String
    var lineNum: Int = 0

    var id: String { "\(type):\(lineNum):\(content.hashValue)" }
}

// MARK: - Parser

enum DiffParser {

    /// Ports `parseDiff()` from ChangesView.svelte line-for-line: same
    /// state machine, same metadata lines skipped, same hunk-header regex
    /// semantics, same add/del/ctx bucketing. `annotateHunks` is folded in
    /// automatically so callers always get fully-annotated files back.
    static func parse(_ raw: String) -> [DiffFile] {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var result: [DiffFile] = []
        var currentFile: DiffFile?
        var currentHunkIndex: Int?
        // Binary-file detection: a file section whose only body line is
        // "Binary files a/x and b/y differ" (no `--- `/`+++ `/hunks at
        // all in some git configurations, but always includes this line
        // when it does appear) -- the web app skips these; flag them.
        var sawBinaryMarker = false
        // Fallback names parsed from "diff --git a/X b/Y". The ported
        // parseDiff() never reads this line for names (only `--- `/`+++ `
        // are used, matching the source exactly) -- but a pure rename
        // (100% similarity) or a binary-only diff has NEITHER line, which
        // would make `displayName` fall back to "(unknown)" even though
        // the real file name is sitting right there in the header. Not a
        // behavior change to the ported algorithm's real-content parsing
        // -- only a fallback for names, used only when `--- `/`+++ ` never
        // set them.
        var headerOldName = ""
        var headerNewName = ""

        let lines = raw.components(separatedBy: "\n")

        func flushCurrentFile() {
            if var file = currentFile {
                file.isBinary = sawBinaryMarker
                if file.oldName.isEmpty { file.oldName = headerOldName }
                if file.newName.isEmpty { file.newName = headerNewName }
                result.append(file)
            }
            currentFile = nil
            currentHunkIndex = nil
            sawBinaryMarker = false
            headerOldName = ""
            headerNewName = ""
        }

        for line in lines {
            if line.hasPrefix("diff --git") || line.hasPrefix("diff --no-index") {
                flushCurrentFile()
                currentFile = DiffFile(oldName: "", newName: "", hunks: [], additions: 0, deletions: 0, isBinary: false)
                (headerOldName, headerNewName) = parseGitHeaderNames(line)
                continue
            }
            guard currentFile != nil else { continue }

            if line.hasPrefix("--- ") {
                currentFile!.oldName = stripDiffPrefix(line.dropFirst(4).description, marker: "a/")
                continue
            }
            if line.hasPrefix("+++ ") {
                currentFile!.newName = stripDiffPrefix(line.dropFirst(4).description, marker: "b/")
                continue
            }

            if line.hasPrefix("index ") || line.hasPrefix("new file") || line.hasPrefix("deleted file") ||
                line.hasPrefix("old mode") || line.hasPrefix("new mode") || line.hasPrefix("similarity") ||
                line.hasPrefix("rename from") || line.hasPrefix("rename to") {
                continue
            }
            if line.hasPrefix("Binary files") {
                sawBinaryMarker = true
                continue
            }

            if line.hasPrefix("@@") {
                if let hunk = parseHunkHeader(line) {
                    currentFile!.hunks.append(hunk)
                    currentHunkIndex = currentFile!.hunks.count - 1
                    continue
                }
            }

            guard let hi = currentHunkIndex else { continue }
            let first = line.first
            if first == "+" {
                currentFile!.hunks[hi].lines.append(DiffLine(type: .add, content: String(line.dropFirst())))
                currentFile!.additions += 1
            } else if first == "-" {
                currentFile!.hunks[hi].lines.append(DiffLine(type: .del, content: String(line.dropFirst())))
                currentFile!.deletions += 1
            } else if first == " " || line.isEmpty {
                let content = first == " " ? String(line.dropFirst()) : ""
                currentFile!.hunks[hi].lines.append(DiffLine(type: .ctx, content: content))
            } else if first == "\\" {
                continue // "\ No newline at end of file"
            }
        }
        flushCurrentFile()

        for i in result.indices {
            annotateHunks(&result[i])
        }
        return result
    }

    /// Fallback-only name parser for "diff --git a/OLD b/NEW" header lines
    /// (see the comment at `headerOldName`/`headerNewName` above for why
    /// this exists). Handles the common unquoted case; paths containing a
    /// literal " b/" are a genuine ambiguity in this header format that git
    /// itself resolves by quoting (`diff --git "a/x b/y" "b/x b/y"`) -- not
    /// handled here since `--- `/`+++ ` lines cover that case in practice.
    private static func parseGitHeaderNames(_ line: String) -> (old: String, new: String) {
        var rest = line
        for prefix in ["diff --git ", "diff --no-index "] where rest.hasPrefix(prefix) {
            rest = String(rest.dropFirst(prefix.count))
        }
        guard let separatorRange = rest.range(of: " b/") else { return ("", "") }
        var old = String(rest[rest.startIndex..<separatorRange.lowerBound])
        if old.hasPrefix("a/") { old = String(old.dropFirst(2)) }
        let new = String(rest[separatorRange.upperBound...])
        return (old, new)
    }

    /// `--- a/foo` -> `foo`, `--- /dev/null` -> `/dev/null` — matches the
    /// svelte regex replacements `.replace(/^a\//, '').replace(/^\/dev\/null$/, '/dev/null')`
    /// (the /dev/null branch is a no-op by construction; kept only for
    /// parity/readability with the source it's ported from).
    private static func stripDiffPrefix(_ s: String, marker: String) -> String {
        if s == "/dev/null" { return "/dev/null" }
        if s.hasPrefix(marker) { return String(s.dropFirst(marker.count)) }
        return s
    }

    /// `@@ -oldStart,oldLines +newStart,newLines @@ context` — oldLines/
    /// newLines are parsed by the regex in the source but never stored on
    /// the hunk (annotateHunks recomputes position by walking `lines`), so
    /// this only keeps oldStart/newStart/context, matching the JS object
    /// shape `{header, oldStart, newStart, context, lines}` exactly.
    private static func parseHunkHeader(_ line: String) -> DiffHunk? {
        // ^@@\s+-?(\d+)(?:,(\d+))?\s+\+?(\d+)(?:,(\d+))?\s+@@(.*)
        guard let regex = Self.hunkHeaderRegex else { return nil }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard let oldStart = Int(ns.substring(with: m.range(at: 1))),
              let newStart = Int(ns.substring(with: m.range(at: 3))) else { return nil }
        let context = m.range(at: 5).location != NSNotFound ? ns.substring(with: m.range(at: 5)) : ""
        return DiffHunk(header: line, oldStart: oldStart, newStart: newStart, context: context, lines: [])
    }

    private static let hunkHeaderRegex = try? NSRegularExpression(
        pattern: #"^@@\s+-?(\d+)(?:,(\d+))?\s+\+?(\d+)(?:,(\d+))?\s+@@(.*)"#
    )

    /// Walks each hunk's lines assigning `lineNum`: add/ctx lines advance
    /// (and receive) the NEW-file counter, del/ctx lines advance the
    /// OLD-file counter — ctx lines get the new-file number, exactly
    /// `annotateHunks()` in the svelte source.
    private static func annotateHunks(_ file: inout DiffFile) {
        for hi in file.hunks.indices {
            var oldLine = file.hunks[hi].oldStart
            var newLine = file.hunks[hi].newStart
            for li in file.hunks[hi].lines.indices {
                switch file.hunks[hi].lines[li].type {
                case .add:
                    file.hunks[hi].lines[li].lineNum = newLine
                    newLine += 1
                case .del:
                    file.hunks[hi].lines[li].lineNum = oldLine
                    oldLine += 1
                case .ctx:
                    file.hunks[hi].lines[li].lineNum = newLine
                    newLine += 1
                    oldLine += 1
                }
            }
        }
    }
}

// MARK: - Threshold logic (ported from applySmartFileCollapse / render gating)

enum DiffThresholds {
    /// `diffSize > 100000 || files.length > 15 || totalLines > 1000` —
    /// verbatim from `applySmartFileCollapse()` in ChangesView.svelte.
    static func shouldAutoCollapse(diffSizeBytes: Int, files: [DiffFile]) -> Bool {
        let totalLines = files.reduce(0) { $0 + $1.totalLines }
        return diffSizeBytes > 100_000 || files.count > 15 || totalLines > 1_000
    }

    /// Per-file exception to auto-collapse: `fileLines < 20 || fileChanges
    /// < 10 || idx < 2` — verbatim from the same function's per-file loop.
    static func keepExpandedByDefault(file: DiffFile, index: Int) -> Bool {
        file.totalLines < 20 || file.totalChanges < 10 || index < 2
    }

    /// `diffSize > 1000000` (1MB) — verbatim from `loadDiff()`.
    static func isPerformanceMode(diffSizeBytes: Int) -> Bool {
        diffSizeBytes > 1_000_000
    }

    /// `fileLines > 200` — verbatim from the render block's `isLargeFile`.
    static func isLargeFile(_ file: DiffFile) -> Bool {
        file.totalLines > 200
    }

    /// Default hunks shown for a large file: `Math.min(file.hunks.length, 3)`.
    /// Non-large files show all hunks immediately.
    static func defaultHunksToShow(for file: DiffFile) -> Int {
        isLargeFile(file) ? min(file.hunks.count, 3) : file.hunks.count
    }

    /// "Show more hunks" batch size: `Math.min(currentHunks + 5, file.hunks.length)`.
    static func nextHunksToShow(current: Int, file: DiffFile) -> Int {
        min(current + 5, file.hunks.count)
    }
}
