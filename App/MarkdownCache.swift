import Foundation
import MarkdownUI

/// Caches parsed `MarkdownContent` by message identity, not by string
/// equality -- a message's content never changes once persisted (only the
/// one streaming preview does, and that path never touches this cache; see
/// `AssistantText`), so `sequence` alone is a safe, cheap cache key.
///
/// Why this exists at all: `MarkdownUI.Markdown(_:)` re-parses its cmark AST
/// from scratch every time its `body` is evaluated, and it has no cache of
/// its own (checked: `Sources/MarkdownUI/Parser/MarkdownParser.swift` has no
/// memoization). SwiftUI re-evaluates a row's `body` for reasons that have
/// nothing to do with that row's own content -- a sibling grouped-tool-call
/// card toggling `expanded`, a `ScrollViewReader` proxy call, the keyboard
/// showing -- so without a cache, scrolling a long session with several
/// code-block-heavy replies would re-run the markdown parser on every one of
/// those unrelated updates. `NSCache` evicts under memory pressure on its
/// own, matching a chat history that can run to hundreds of messages.
@MainActor
final class MarkdownCache {
    static let shared = MarkdownCache()

    private let store = NSCache<NSNumber, CachedEntry>()

    private init() {
        // A parsed AST is small (KBs, not MBs) even for a long reply, so the
        // limit exists to bound worst-case memory on a session with an
        // enormous number of long messages, not because parsed markdown is
        // itself heavy.
        store.countLimit = 500
    }

    /// Wraps `MarkdownContent` so it satisfies `NSCache`'s reference-type
    /// requirement without making the content type itself a class.
    private final class CachedEntry {
        let content: MarkdownContent
        init(_ content: MarkdownContent) { self.content = content }
    }

    func content(for message: Message) -> MarkdownContent {
        let key = NSNumber(value: message.sequence)
        if let cached = store.object(forKey: key) {
            return cached.content
        }
        let parsed = MarkdownContent(message.content ?? "")
        store.setObject(CachedEntry(parsed), forKey: key)
        return parsed
    }
}
