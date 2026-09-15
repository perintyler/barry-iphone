import SwiftUI

/// Caches `SyntaxHighlighter.highlight(...)` results -- same reasoning as
/// `MarkdownCache`: SwiftUI re-evaluates a row's `body` for reasons that
/// have nothing to do with that row's own content (a sibling card
/// expanding, a scroll-position preference update), and regex tokenization
/// across many diff lines is real, avoidable work if it reruns on every
/// such re-render. `NSCache` evicts under memory pressure, matching a large
/// diff that can run to thousands of lines.
@MainActor
final class SyntaxHighlightCache {
    static let shared = SyntaxHighlightCache()

    private let store = NSCache<NSString, CachedEntry>()

    private init() {
        // A highlighted line is small (one AttributedString per line), so
        // this bounds worst-case memory on an enormous diff rather than
        // reflecting real per-entry cost.
        store.countLimit = 5000
    }

    private final class CachedEntry {
        let content: AttributedString
        init(_ content: AttributedString) { self.content = content }
    }

    /// Keyed on language + line kind (add/del/context -- their base text
    /// colors differ) + the line's own content -- a cached "add" line's
    /// tokens must never be served for an identical-text "del" line, since
    /// their base colors differ. Deliberately NOT keyed on `Color` itself:
    /// `Color` has no stable, cheap string representation to build a cache
    /// key from, and `DiffLine.Kind` is exactly the real distinguishing
    /// signal anyway -- the color is a pure function of the kind, one
    /// level removed.
    func highlighted(_ line: String, language: SyntaxLanguage, kind: DiffLine.Kind, baseColor: Color) -> AttributedString {
        let key = "\(language)|\(kind)|\(line)" as NSString
        if let cached = store.object(forKey: key) {
            return cached.content
        }
        let result = SyntaxHighlighter.highlight(line, language: language, baseColor: baseColor)
        store.setObject(CachedEntry(result), forKey: key)
        return result
    }
}
