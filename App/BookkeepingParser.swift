import Foundation

// MARK: - Parsed bookkeeping model

/// One timestamped ledger entry from `session.summary` — a scheduled
/// (~15-minute) job appends one of these in a fixed markdown template:
///
///     ### YYYY-MM-DD HH:MM [⚠️ TOPIC CHANGE]
///
///     [Was X; now Y.]
///
///     ### Done
///     ...
///     ### Learnings
///     ...
///     ### What went right
///     ...
///     ### What went wrong
///     ...
///     ### Open loops
///     ...
///     <!-- model: qwen3:4b -->
///
/// Sections are SUPPOSED to be omitted entirely when there's nothing to
/// report, but real captured data shows the header often appears anyway
/// with no body underneath (see `bookkeeping-kpd-real.txt` fixture,
/// 2026-09-14 22:19 entry: `### Done` / `### Learnings` both header-only).
/// Both shapes must produce a nil section here, not an empty-string one --
/// this struct only ever holds sections that genuinely have content.
struct BookkeepingEntry: Identifiable, Equatable {
    var timestamp: Date?
    /// Raw `YYYY-MM-DD HH:MM` text from the header, kept for display when
    /// `timestamp` fails to parse (still show something rather than
    /// nothing) and for a stable id independent of Date's Equatable quirks.
    var timestampRaw: String
    var isDrift: Bool
    /// "Was X; now Y." -- only present when `isDrift` is true.
    var driftDescription: String?
    var done: String?
    var learnings: String?
    var wentRight: String?
    var wentWrong: String?
    var openLoops: String?
    /// e.g. "qwen3:4b" from the trailing `<!-- model: qwen3:4b -->` comment
    /// -- stripped from every other field's content, kept here as its own
    /// small provenance field per the mockup's "qwen3:4b · 15-min
    /// bookkeeping pass, not the live model" label.
    var model: String?

    var id: String { timestampRaw }

    var hasAnySection: Bool {
        done != nil || learnings != nil || wentRight != nil || wentWrong != nil || openLoops != nil
    }
}

// MARK: - Parser

enum BookkeepingParser {

    private static let entryHeaderRegex = try? NSRegularExpression(
        pattern: #"^### (\d{4}-\d{2}-\d{2} \d{2}:\d{2})(?: (⚠️ TOPIC CHANGE))?\s*$"#
    )

    private static let sectionHeaderRegex = try? NSRegularExpression(
        pattern: #"^### (Done|Learnings|What went right|What went wrong|Open loops)\s*$"#
    )

    private static let modelCommentRegex = try? NSRegularExpression(
        pattern: #"<!--\s*model:\s*(.+?)\s*-->"#
    )

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Splits a raw `session.summary` string into ledger entries,
    /// most-recent-first is NOT applied here -- entries come back in the
    /// order they appear in the raw text (oldest first, since the job
    /// appends); callers that want most-recent-first (the mockup's
    /// timeline) reverse the result themselves.
    static func parse(_ raw: String?) -> [BookkeepingEntry] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var entries: [BookkeepingEntry] = []
        var current: BookkeepingEntry?
        var currentSection: String?
        var buffer: [String] = []

        func flushSection() {
            guard let section = currentSection else { return }
            let text = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = []
            currentSection = nil
            guard !text.isEmpty else { return }
            switch section {
            case "Done": current?.done = text
            case "Learnings": current?.learnings = text
            case "What went right": current?.wentRight = text
            case "What went wrong": current?.wentWrong = text
            case "Open loops": current?.openLoops = text
            default: break
            }
        }

        func flushEntry() {
            flushSection()
            if let entry = current {
                entries.append(entry)
            }
            current = nil
        }

        let lines = raw.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let ns = line as NSString

            if let regex = entryHeaderRegex,
               let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                flushEntry()
                let ts = ns.substring(with: m.range(at: 1))
                let isDrift = m.range(at: 2).location != NSNotFound
                var entry = BookkeepingEntry(
                    timestamp: timestampFormatter.date(from: ts),
                    timestampRaw: ts,
                    isDrift: isDrift,
                    driftDescription: nil,
                    done: nil, learnings: nil, wentRight: nil, wentWrong: nil, openLoops: nil,
                    model: nil
                )
                // A drift entry's next non-blank line is the "Was X; now Y."
                // description, sitting between the header and the first
                // "### Done" section header.
                if isDrift {
                    var j = i + 1
                    while j < lines.count && lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                    if j < lines.count {
                        let candidate = lines[j].trimmingCharacters(in: .whitespaces)
                        if !candidate.hasPrefix("###") && !candidate.isEmpty {
                            entry.driftDescription = candidate
                            i = j
                        }
                    }
                }
                current = entry
                i += 1
                continue
            }

            if current != nil, let regex = sectionHeaderRegex,
               let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                flushSection()
                currentSection = ns.substring(with: m.range(at: 1))
                i += 1
                continue
            }

            // Trailing provenance comment: strip from body content, capture
            // the model name onto the entry currently being built.
            if let regex = modelCommentRegex,
               let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                if current != nil {
                    current!.model = ns.substring(with: m.range(at: 1))
                }
                i += 1
                continue
            }

            if current != nil {
                if currentSection != nil {
                    buffer.append(line)
                }
                // Lines between the entry header/drift line and the first
                // "### Section" header (i.e. currentSection == nil) are
                // ignored -- observed real data has none, but this keeps
                // parsing defensive rather than crashing/misattributing.
            }
            i += 1
        }
        flushEntry()

        return entries
    }
}
