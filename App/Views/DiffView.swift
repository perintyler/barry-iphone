import SwiftUI

/// The diff viewer screen: mode toggle (uncommitted / vs branch), stats
/// bar, collapsible file list, hunk rendering with the mockup's add/del
/// color scheme, hunk paging for huge files, and a performance-mode
/// banner for very large diffs. Pushed from `ChatView`'s toolbar.
struct DiffView: View {
    let session: Session
    let client: BarryClient

    @State private var mode: DiffMode = .uncommitted
    @State private var raw: SessionDiff?
    @State private var files: [DiffFile] = []
    @State private var loading = true
    @State private var errorMessage: String?

    /// Files the user has manually expanded or collapsed, overriding the
    /// smart-collapse default for that index.
    @State private var overrides: [Int: Bool] = [:]
    /// How many hunks are currently shown per large-file index.
    @State private var hunksShown: [Int: Int] = [:]
    /// Per-file performance-mode "content loaded" override — only
    /// meaningful when `performanceMode` is true.
    @State private var contentLoaded: Set<Int> = []

    init(session: Session, config: ServerConfig) {
        self.session = session
        self.client = BarryClient(config: config)
    }

    private var diffSizeBytes: Int { raw?.diffSizeBytes ?? 0 }
    private var autoCollapse: Bool { DiffThresholds.shouldAutoCollapse(diffSizeBytes: diffSizeBytes, files: files) }
    private var performanceMode: Bool { DiffThresholds.isPerformanceMode(diffSizeBytes: diffSizeBytes) }

    private func isExpanded(_ index: Int) -> Bool {
        if let override = overrides[index] { return override }
        guard autoCollapse else { return true }
        return DiffThresholds.keepExpandedByDefault(file: files[index], index: index)
    }

    var body: some View {
        VStack(spacing: 0) {
            modeToggle
            statsBar
            content
        }
        .navigationTitle("Changes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Refresh") { Task { await load() } }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("diffOverflowMenu")
            }
        }
        .task { await load() }
        .onChange(of: mode) { _, _ in Task { await load() } }
    }

    // MARK: Mode toggle

    private var modeToggle: some View {
        HStack(spacing: 2) {
            modeButton(.uncommitted, label: "Uncommitted")
            modeButton(.branch, label: "vs \(raw?.baseBranch ?? "master")")
        }
        .padding(4)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func modeButton(_ m: DiffMode, label: String) -> some View {
        Button {
            mode = m
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .foregroundStyle(mode == m ? Theme.accent : Color.secondary)
                .background(mode == m ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityIdentifier(m == .uncommitted ? "diffModeUncommitted" : "diffModeBranch")
    }

    // MARK: Stats bar

    private var statsBar: some View {
        HStack(spacing: 6) {
            if loading {
                ProgressView().controlSize(.small)
                Text("Loading changes…")
                    .foregroundStyle(.tertiary)
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if files.isEmpty {
                Text(cleanMessage)
                    .foregroundStyle(.tertiary)
            } else {
                Text("\(files.count) file\(files.count == 1 ? "" : "s")")
                Dot()
                (Text("+\(totalAdditions)").foregroundStyle(Theme.Diff.addText)
                 + Text(" ")
                 + Text("-\(totalDeletions)").foregroundStyle(Theme.Diff.delText))
                Dot()
                Text(humanSize(diffSizeBytes))
            }
            Spacer()
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var cleanMessage: String {
        switch mode {
        case .uncommitted: return "Working tree is clean"
        case .branch: return raw?.onMainBranch == true ? "Working tree is clean on \(raw?.baseBranch ?? "master")" : "No changes vs \(raw?.baseBranch ?? "master")"
        case .commit: return "No changes"
        }
    }

    private var totalAdditions: Int { files.reduce(0) { $0 + $1.additions } }
    private var totalDeletions: Int { files.reduce(0) { $0 + $1.deletions } }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if loading {
            Spacer()
        } else if let errorMessage, files.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load diff", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Retry") { Task { await load() } }
            }
            Spacer()
        } else if files.isEmpty {
            ContentUnavailableView("No changes", systemImage: "checkmark.circle")
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        DiffFileSection(
                            file: file,
                            index: index,
                            isExpanded: isExpanded(index),
                            isOutlier: isOutlier(file),
                            performanceMode: performanceMode,
                            contentLoaded: contentLoaded.contains(index),
                            hunksShown: hunksShown[index] ?? DiffThresholds.defaultHunksToShow(for: file),
                            onToggle: { overrides[index] = !isExpanded(index) },
                            onLoadContent: { contentLoaded.insert(index) },
                            onShowMoreHunks: {
                                let current = hunksShown[index] ?? DiffThresholds.defaultHunksToShow(for: file)
                                hunksShown[index] = DiffThresholds.nextHunksToShow(current: current, file: file)
                            }
                        )
                    }
                    if autoCollapse {
                        perfBanner
                    }
                }
            }
        }
    }

    /// The mockup flags one conspicuously huge file (their example: 5846
    /// lines / 189KB) in accent color in the collapsed list itself. There's
    /// no server-provided "this is the outlier" flag, so this treats any
    /// file at or above that same order of magnitude (>= 2000 lines, a
    /// round threshold comfortably below the mockup's example and well
    /// above ordinary files) as the same signal.
    private func isOutlier(_ file: DiffFile) -> Bool {
        file.totalLines >= 2000
    }

    private var perfBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("⚡").font(.system(size: 12))
                Text("Some files auto-collapsed.").font(.system(size: 10.5, weight: .bold))
            }
            Text("Everything under ~20 lines stayed open — tap any row to expand.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator), lineWidth: 1))
        .opacity(0.85)
        .padding(16)
    }

    // MARK: Loading

    private func load() async {
        loading = true
        errorMessage = nil
        overrides = [:]
        hunksShown = [:]
        contentLoaded = []
        do {
            let response = try await client.diff(sessionId: session.id, mode: mode)
            raw = response
            files = DiffParser.parse(response.diff)
        } catch {
            errorMessage = error.localizedDescription
            files = []
        }
        loading = false
    }
}

private func humanSize(_ bytes: Int) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
    return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
}

private struct Dot: View {
    var body: some View {
        Text("·").foregroundStyle(.tertiary)
    }
}

// MARK: - File section

private struct DiffFileSection: View {
    let file: DiffFile
    let index: Int
    let isExpanded: Bool
    let isOutlier: Bool
    let performanceMode: Bool
    let contentLoaded: Bool
    let hunksShown: Int
    let onToggle: () -> Void
    let onLoadContent: () -> Void
    let onShowMoreHunks: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                if file.isBinary {
                    binaryRow
                } else if performanceMode && !contentLoaded {
                    performanceSummary
                } else {
                    hunksView
                }
            }
        }
        .background(isOutlier ? Theme.accentSoft.opacity(0.4) : Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var header: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                fileNameLabel
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if file.isNewFile {
                    // Always accent-colored per the mockup, regardless of
                    // outlier status -- the NEW badge and the outlier
                    // flagging are independent signals that happen to
                    // share a color.
                    Text("NEW")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                }
                statLabel
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var fileNameLabel: Text {
        let font = Font.system(size: 11.5, design: .monospaced)
        let name = file.displayName
        if let slashIndex = name.lastIndex(of: "/") {
            let dir = String(name[name.startIndex...slashIndex])
            let base = String(name[name.index(after: slashIndex)...])
            return Text(dir).font(font).foregroundStyle(isOutlier ? Theme.accent.opacity(0.7) : Color(.tertiaryLabel))
                + Text(base).font(font).bold(isOutlier).foregroundStyle(isOutlier ? Theme.accent : Color.primary)
        }
        return Text(name).font(font).bold(isOutlier).foregroundStyle(isOutlier ? Theme.accent : Color.primary)
    }

    private var statLabel: some View {
        HStack(spacing: 5) {
            if file.additions > 0 {
                Text("+\(file.additions)").foregroundStyle(isOutlier ? Theme.accent : Theme.Diff.addText).bold(isOutlier)
            }
            if file.deletions > 0 {
                Text("-\(file.deletions)").foregroundStyle(Theme.Diff.delText)
            }
        }
        .font(.system(size: 10, design: .monospaced))
    }

    private var binaryRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.fill")
                .foregroundStyle(.tertiary)
            Text("Binary file changed")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
    }

    private var performanceSummary: some View {
        let lineCount = file.hunks.reduce(0) { $0 + $1.lines.count }
        return HStack {
            Text("\(file.hunks.count) hunks, \(lineCount) lines")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Load content", action: onLoadContent)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemFill))
    }

    private var hunksView: some View {
        let isLarge = DiffThresholds.isLargeFile(file)
        let shown = Array(file.hunks.prefix(hunksShown))
        let shownLineCount = shown.reduce(0) { $0 + $1.lines.count }
        let remainingHunks = file.hunks.count - shown.count
        let remainingLines = file.totalLines - shownLineCount

        let language = SyntaxLanguage.detect(fromFilename: file.displayName)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(shown) { hunk in
                DiffHunkView(hunk: hunk, language: language)
            }
            if isLarge && remainingHunks > 0 {
                Button(action: onShowMoreHunks) {
                    Text("Show \(remainingHunks) more hunk\(remainingHunks == 1 ? "" : "s") (\(remainingLines) more lines)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
                        .padding(10)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Hunk

private struct DiffHunkView: View {
    let hunk: DiffHunk
    let language: SyntaxLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 3)
                .background(Theme.accentSoft.opacity(0.85))

            ForEach(hunk.lines) { line in
                DiffLineView(line: line, language: language)
            }
        }
    }
}

private struct DiffLineView: View {
    let line: DiffLine
    let language: SyntaxLanguage

    private var background: Color {
        switch line.type {
        case .add: return Theme.Diff.addBackground
        case .del: return Theme.Diff.delBackground
        case .ctx: return .clear
        }
    }

    private var color: Color {
        switch line.type {
        case .add: return Theme.Diff.addText
        case .del: return Theme.Diff.delText
        case .ctx: return .secondary
        }
    }

    private var gutterText: String {
        switch line.type {
        case .add: return "+"
        case .del: return "-"
        case .ctx: return "\(line.lineNum)"
        }
    }

    private var gutterColor: Color {
        switch line.type {
        case .add: return Theme.Diff.addText
        case .del: return Theme.Diff.delText
        case .ctx: return Color(.tertiaryLabel).opacity(0.6)
        }
    }

    /// Syntax-colored tokens layered on top of `color` (the add/del/context
    /// base text color) -- computed once per line and cached
    /// (`SyntaxHighlightCache`), keyed on language + line kind + content,
    /// so scrolling past an already-rendered line never re-tokenizes it.
    /// Approved mockup: https://claude.ai/code/artifact/e8dcd7a7 -- add/del
    /// backgrounds stay exactly as they are; syntax colors render within
    /// the line, never replacing the diff-identity color scheme.
    private var highlighted: AttributedString {
        let text = line.content.isEmpty ? " " : line.content
        return SyntaxHighlightCache.shared.highlighted(text, language: language, kind: line.type, baseColor: color)
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(gutterText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(gutterColor)
                .frame(width: 20, alignment: .trailing)
                .padding(.leading, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlighted)
                    .font(.system(size: 10.5, design: .monospaced))
                    .lineLimit(1)
                    .padding(.trailing, 8)
            }
        }
        .padding(.leading, 2)
        .background(background)
    }
}
