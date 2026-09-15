import XCTest
import SwiftUI
@testable import Barry

final class SyntaxLanguageTests: XCTestCase {
    func testDetectsSwiftFromExtension() {
        XCTAssertEqual(SyntaxLanguage.detect(fromFilename: "App/Views/ChatView.swift"), .swift)
    }

    func testDetectsTypeScriptVariants() {
        for name in ["route.ts", "component.tsx", "index.js", "App.jsx", "module.mjs"] {
            XCTAssertEqual(SyntaxLanguage.detect(fromFilename: name), .typescript, "\(name) should detect as typescript")
        }
    }

    func testDetectsPython() {
        XCTAssertEqual(SyntaxLanguage.detect(fromFilename: "scripts/build.py"), .python)
    }

    func testDetectsJSON() {
        XCTAssertEqual(SyntaxLanguage.detect(fromFilename: "package.json"), .json)
    }

    func testDetectsYAMLBothExtensions() {
        XCTAssertEqual(SyntaxLanguage.detect(fromFilename: "config.yaml"), .yaml)
        XCTAssertEqual(SyntaxLanguage.detect(fromFilename: "config.yml"), .yaml)
    }

    func testDetectsShell() {
        XCTAssertEqual(SyntaxLanguage.detect(fromFilename: "scripts/deploy.sh"), .shell)
    }

    func testUnrecognizedExtensionFallsBackToPlain() {
        XCTAssertEqual(SyntaxLanguage.detect(fromFilename: "image.png"), .plain)
        XCTAssertEqual(SyntaxLanguage.detect(fromFilename: "README"), .plain, "no extension at all")
    }

    func testCaseInsensitiveExtension() {
        XCTAssertEqual(SyntaxLanguage.detect(fromFilename: "Main.SWIFT"), .swift)
    }
}

final class SyntaxHighlighterTests: XCTestCase {

    /// Real line from this repo's own commit 7806682 (App/Views/ChatView.swift).
    private let realSwiftLine = "                    ForEach(chat.groupedMessages) { item in"

    func testKeywordGetsHighlightedDifferentlyFromBaseColor() {
        let result = SyntaxHighlighter.highlight(realSwiftLine, language: .swift, baseColor: .red)
        // "in" is a Swift keyword in this line; find its foreground color
        // and confirm it's NOT the base (add/del) color -- proves the
        // keyword rule actually fired, not just that highlighting ran.
        guard let inRange = result.range(of: "in", options: .backwards) else {
            return XCTFail("expected to find 'in' in the highlighted result")
        }
        let keywordColor = result[inRange].foregroundColor
        XCTAssertNotNil(keywordColor)
        XCTAssertNotEqual(keywordColor, Color.red, "keyword 'in' must be colored differently from the plain base/add-del color")
    }

    func testNonKeywordTextKeepsBaseColor() {
        let result = SyntaxHighlighter.highlight("plain text with no special tokens at all", language: .swift, baseColor: .red)
        // Sample a run of plain words -- none of these are keywords,
        // strings, comments, numbers, or capitalized (type-like).
        guard let range = result.range(of: "plain") else {
            return XCTFail("expected to find 'plain' in the result")
        }
        XCTAssertEqual(result[range].foregroundColor, .red, "non-token text must keep the base add/del color")
    }

    func testStringLiteralIsHighlighted() {
        let line = #"let message = "hello world""#
        let result = SyntaxHighlighter.highlight(line, language: .swift, baseColor: .green)
        guard let range = result.range(of: "\"hello world\"") else {
            return XCTFail("expected to find the string literal in the result")
        }
        XCTAssertNotEqual(result[range].foregroundColor, Color.green, "string literal must not keep the plain base color")
    }

    func testCommentIsHighlighted() {
        let line = "let x = 1 // a trailing comment"
        let result = SyntaxHighlighter.highlight(line, language: .swift, baseColor: .green)
        guard let range = result.range(of: "// a trailing comment") else {
            return XCTFail("expected to find the comment in the result")
        }
        XCTAssertNotEqual(result[range].foregroundColor, Color.green)
    }

    func testPlainLanguageAppliesNoTokenColoring() {
        // .plain must be a true no-op: every character keeps baseColor,
        // even text that LOOKS like it has keywords/strings/numbers.
        let line = #"func "quoted" 123 // comment"#
        let result = SyntaxHighlighter.highlight(line, language: .plain, baseColor: .blue)
        for run in result.runs {
            XCTAssertEqual(run.foregroundColor, .blue, "plain language must never color any token")
        }
    }

    func testEmptyLineProducesEmptyResultWithoutCrashing() {
        let result = SyntaxHighlighter.highlight("", language: .swift, baseColor: .red)
        XCTAssertEqual(String(result.characters), "")
    }

    /// Different languages' keyword sets are genuinely different -- "def"
    /// is a Python keyword but not a Swift one, proving the language
    /// parameter actually selects a distinct rule set rather than one
    /// generic pass.
    func testKeywordSetsDifferByLanguage() {
        let line = "def foo():"
        let pythonResult = SyntaxHighlighter.highlight(line, language: .python, baseColor: .red)
        let swiftResult = SyntaxHighlighter.highlight(line, language: .swift, baseColor: .red)

        guard let pyRange = pythonResult.range(of: "def"),
              let swiftRange = swiftResult.range(of: "def") else {
            return XCTFail("expected to find 'def' in both results")
        }
        XCTAssertNotEqual(pythonResult[pyRange].foregroundColor, Color.red, "'def' is a Python keyword")
        XCTAssertEqual(swiftResult[swiftRange].foregroundColor, Color.red, "'def' is not a Swift keyword -- must keep base color")
    }
}

@MainActor
final class SyntaxHighlightCacheTests: XCTestCase {

    func testRepeatedLookupReturnsEquivalentContent() {
        let cache = SyntaxHighlightCache.shared
        let line = "let cached = true"
        let first = cache.highlighted(line, language: .swift, kind: .add, baseColor: .green)
        let second = cache.highlighted(line, language: .swift, kind: .add, baseColor: .green)
        XCTAssertEqual(first, second)
    }

    /// The exact bug class this cache exists to prevent: identical TEXT on
    /// an add line vs. a del line must NOT share a cache entry, since their
    /// base colors differ. If the cache key omitted `kind`, this would
    /// incorrectly return the add-line's (green-based) colors for the
    /// del-line lookup.
    func testIdenticalTextDifferentKindDoesNotShareCacheEntry() {
        let cache = SyntaxHighlightCache.shared
        let line = "some shared line text for cache key testing"
        let addResult = cache.highlighted(line, language: .plain, kind: .add, baseColor: .green)
        let delResult = cache.highlighted(line, language: .plain, kind: .del, baseColor: .red)

        guard let addRange = addResult.range(of: "some"), let delRange = delResult.range(of: "some") else {
            return XCTFail("expected to find 'some' in both results")
        }
        XCTAssertEqual(addResult[addRange].foregroundColor, .green)
        XCTAssertEqual(delResult[delRange].foregroundColor, .red, "del-kind lookup must not have returned the add-kind's cached (green) result")
    }
}
