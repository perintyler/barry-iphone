import SwiftUI

/// The session bookkeeping timeline: a scheduled (~15-minute) job appends
/// one ledger entry to `session.summary` per pass. This screen lists all
/// parsed entries most-recent-first (per the mockup), flags topic-change
/// drift entries, and pushes a full-screen detail view per entry. No
/// separate summary endpoint exists -- `session.summary` is already present
/// on the `Session` fetched for the chat screen, so this view takes the
/// session directly rather than making its own network call.
struct BookkeepingView: View {
    let session: Session

    private var entries: [BookkeepingEntry] {
        // Parser returns chronological (oldest-first, matching how the job
        // appends); the mockup's timeline is most-recent-first.
        BookkeepingParser.parse(session.summary).reversed()
    }

    var body: some View {
        content
            .navigationTitle("Bookkeeping")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(entries) { entry in
                        NavigationLink {
                            BookkeepingEntryDetailView(entry: entry)
                        } label: {
                            BookkeepingEntryCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .accessibilityIdentifier("bookkeepingTimeline")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No bookkeeping yet",
            systemImage: "clock.badge.questionmark",
            description: Text("Barry appends a bookkeeping entry roughly every 15 minutes while this session runs. Check back once it's been going a little while.")
        )
        .accessibilityIdentifier("bookkeepingEmptyState")
    }
}

// MARK: - Timeline card

private struct BookkeepingEntryCard: View {
    let entry: BookkeepingEntry

    private var previewText: String? {
        entry.done ?? entry.learnings ?? entry.wentRight ?? entry.wentWrong ?? entry.openLoops
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            if entry.isDrift, let driftDescription = entry.driftDescription {
                Text(driftDescription)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let previewText {
                Text(previewText)
                    .font(.system(size: 11))
                    .foregroundStyle(entry.hasAnySection ? Color.primary : .secondary)
                    .lineLimit(3)
            } else {
                Text("Nothing to report this tick.")
                    .font(.system(size: 11))
                    .italic()
                    .foregroundStyle(.tertiary)
            }
            if entry.hasAnySection {
                sectionChips
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(entry.isDrift ? Theme.accentSoft : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(entry.isDrift ? Theme.accent : Color(.separator), lineWidth: entry.isDrift ? 1 : 0.5)
        )
        .opacity(entry.hasAnySection || entry.isDrift ? 1 : 0.75)
        .accessibilityIdentifier(entry.isDrift ? "bookkeepingDriftEntry" : "bookkeepingEntry")
    }

    private var header: some View {
        HStack(spacing: 6) {
            if entry.isDrift {
                Text("⚠️").font(.system(size: 9))
                Text("TOPIC CHANGED")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .tracking(0.3)
            } else {
                Text("Entry")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(entry.displayTime)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private var sectionChips: some View {
        HStack(spacing: 5) {
            if entry.done != nil { chip("done") }
            if entry.learnings != nil { chip("learning") }
            if entry.wentRight != nil { chip("went right") }
            if entry.wentWrong != nil { chip("went wrong") }
            if entry.openLoops != nil { chip("open loop") }
        }
    }

    private func chip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 8.5))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Expanded entry

private struct BookkeepingEntryDetailView: View {
    let entry: BookkeepingEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if entry.isDrift, let driftDescription = entry.driftDescription {
                    driftBanner(driftDescription)
                }
                section("Done", text: entry.done, color: Theme.Bookkeeping.success)
                section("Learnings", text: entry.learnings, color: Theme.accent)
                section("What went right", text: entry.wentRight, color: Theme.Bookkeeping.success)
                section("What went wrong", text: entry.wentWrong, color: Theme.Bookkeeping.danger)
                section("Open loops", text: entry.openLoops, color: Theme.Bookkeeping.warn)
                if !entry.hasAnySection {
                    Text("Nothing to report this tick.")
                        .font(.system(size: 12.5))
                        .italic()
                        .foregroundStyle(.tertiary)
                        .padding(16)
                }
                if let model = entry.model {
                    Divider().padding(.horizontal, 14)
                    Text("\(model) · 15-min bookkeeping pass, not the live model")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .padding(14)
                }
            }
        }
        .navigationTitle("\(entry.displayTime) · Entry")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("bookkeepingEntryDetail")
    }

    private func driftBanner(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text("⚠️").font(.system(size: 11))
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(12)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent, lineWidth: 1))
        .padding(12)
    }

    @ViewBuilder
    private func section(_ title: String, text: String?, color: Color) -> some View {
        if let text {
            VStack(alignment: .leading, spacing: 7) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(color)
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Display helpers

private extension BookkeepingEntry {
    /// "02:36" from a raw "2026-09-15 02:36" header -- matches the
    /// mockup's compact time-only display in the timeline and nav title.
    var displayTime: String {
        if let range = timestampRaw.range(of: #"\d{2}:\d{2}$"#, options: .regularExpression) {
            return String(timestampRaw[range])
        }
        return timestampRaw
    }
}
