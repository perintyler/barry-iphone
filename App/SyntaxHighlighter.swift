import SwiftUI

/// Languages the diff viewer can tokenize -- covers what Barry sessions
/// actually touch (this repo's own stack plus common scripting/config),
/// not a general-purpose language list. Anything else renders as plain
/// monospaced text, same as today.
enum SyntaxLanguage: Equatable {
    case swift, typescript, python, json, yaml, shell, markdown
    case plain

    /// Picked from the file extension -- the same signal `DiffFile`
    /// already carries via `newName`/`oldName`, so no new detection
    /// mechanism is needed.
    static func detect(fromFilename filename: String) -> SyntaxLanguage {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .swift
        case "ts", "tsx", "js", "jsx", "mjs", "cjs": return .typescript
        case "py": return .python
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "sh", "bash", "zsh": return .shell
        case "md", "markdown": return .markdown
        default: return .plain
        }
    }
}

/// Regex-based, per-language tokenizer producing an `AttributedString` with
/// colored ranges for keywords, strings, comments, numbers, and (for a
/// handful of languages) types/function-call position. Deliberately NOT a
/// full parser -- a diff line is often a syntactically incomplete fragment
/// (mid-hunk, no matching brace), which a real parser would choke on but a
/// regex pass tolerates by design.
///
/// `HighlightSwift` (bundles highlight.js, runs through JavaScriptCore) was
/// considered and rejected: no commits since late 2024, and running a JS
/// engine per line for six known languages is real overhead this narrower,
/// native approach avoids entirely.
enum SyntaxHighlighter {
    /// Tint tokens -- kept separate from `Theme` (the app-wide color
    /// vocabulary) because these are specifically calibrated to sit inside
    /// the diff viewer's existing add/del background tints without
    /// clashing; a keyword rendered in the same violet as `Theme.accent`
    /// would visually compete with the accent-colored hunk header above it.
    private static func color(for token: TokenKind) -> Color {
        switch token {
        case .keyword: return Color(red: 0.78, green: 0.57, blue: 0.92)
        case .string: return Color(red: 0.54, green: 0.79, blue: 0.47)
        case .comment: return Color(.tertiaryLabel)
        case .number: return Color(red: 0.90, green: 0.71, blue: 0.40)
        case .type: return Color(red: 0.37, green: 0.77, blue: 0.84)
        case .function: return Color(red: 0.51, green: 0.67, blue: 1.0)
        }
    }

    private enum TokenKind {
        case keyword, string, comment, number, type, function
    }

    private struct Rule {
        let pattern: NSRegularExpression
        let kind: TokenKind
    }

    private static let keywordSets: [SyntaxLanguage: Set<String>] = [
        .swift: ["func", "var", "let", "if", "else", "guard", "return", "struct", "class",
                 "enum", "protocol", "extension", "import", "private", "public", "internal",
                 "fileprivate", "static", "self", "Self", "in", "for", "while", "switch",
                 "case", "default", "break", "continue", "throw", "throws", "try", "catch",
                 "async", "await", "nil", "true", "false", "init", "deinit", "typealias",
                 "where", "as", "is", "super", "weak", "unowned", "lazy", "mutating"],
        .typescript: ["function", "const", "let", "var", "if", "else", "return", "class",
                      "interface", "type", "enum", "import", "export", "default", "from",
                      "async", "await", "for", "while", "switch", "case", "break", "continue",
                      "throw", "try", "catch", "finally", "new", "this", "extends", "implements",
                      "public", "private", "protected", "static", "readonly", "null", "undefined",
                      "true", "false", "void", "typeof", "instanceof", "in", "of"],
        .python: ["def", "class", "if", "elif", "else", "return", "import", "from", "as",
                  "for", "while", "break", "continue", "pass", "try", "except", "finally",
                  "raise", "with", "lambda", "yield", "async", "await", "None", "True", "False",
                  "and", "or", "not", "in", "is", "self", "global", "nonlocal", "assert", "del"],
        .shell: ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case",
                 "esac", "function", "return", "export", "local", "readonly", "set", "unset",
                 "echo", "exit", "break", "continue", "in"],
        .yaml: [],
        .json: [],
        .markdown: [],
        .plain: [],
    ]

    /// Highlights `line` for `language`, returning an `AttributedString`
    /// with colored ranges layered on top of `baseColor` (the diff add/del
    /// text color) -- syntax tokens override the base color where they
    /// match, everything else keeps it, so the add/del identity of the
    /// line is never lost even when highlighted.
    static func highlight(_ line: String, language: SyntaxLanguage, baseColor: Color) -> AttributedString {
        var result = AttributedString(line)
        result.foregroundColor = baseColor
        guard language != .plain, !line.isEmpty else { return result }

        for match in commentMatches(line, language: language) {
            apply(.comment, range: match, in: &result, source: line)
        }
        for match in stringMatches(line, language: language) {
            apply(.string, range: match, in: &result, source: line)
        }
        for match in numberMatches(line) {
            apply(.number, range: match, in: &result, source: line)
        }
        if let keywords = keywordSets[language], !keywords.isEmpty {
            for match in keywordMatches(line, keywords: keywords) {
                apply(.keyword, range: match, in: &result, source: line)
            }
        }
        for match in typeMatches(line, language: language) {
            apply(.type, range: match, in: &result, source: line)
        }
        return result
    }

    private static func apply(_ kind: TokenKind, range nsRange: NSRange, in result: inout AttributedString, source: String) {
        guard let range = Range(nsRange, in: source),
              let attrRange = Range(range, in: result) else { return }
        result[attrRange].foregroundColor = color(for: kind)
    }

    // MARK: - Per-token-kind matchers

    private static func keywordMatches(_ line: String, keywords: Set<String>) -> [NSRange] {
        // Word-boundary match against the keyword set, not a single mega-
        // regex per language -- keeps the keyword lists above as plain
        // data (easy to extend) rather than baked into pattern strings.
        let pattern = try? NSRegularExpression(pattern: #"\b[A-Za-z_][A-Za-z0-9_]*\b"#)
        guard let pattern else { return [] }
        let nsLine = line as NSString
        return pattern.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            .map(\.range)
            .filter { keywords.contains(nsLine.substring(with: $0)) }
    }

    private static let stringPatterns: [SyntaxLanguage: NSRegularExpression] = {
        // Double- or single-quoted strings, not attempting to handle
        // escaped-quote edge cases perfectly -- a diff line is display-only
        // text, not source being compiled, so a rare mis-boundary on an
        // escaped quote costs nothing beyond one line's coloring.
        let pattern = try? NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'"#)
        guard let pattern else { return [:] }
        return [.swift: pattern, .typescript: pattern, .python: pattern, .json: pattern, .shell: pattern]
    }()

    private static func stringMatches(_ line: String, language: SyntaxLanguage) -> [NSRange] {
        guard let pattern = stringPatterns[language] else { return [] }
        let nsLine = line as NSString
        return pattern.matches(in: line, range: NSRange(location: 0, length: nsLine.length)).map(\.range)
    }

    private static let commentPatterns: [SyntaxLanguage: NSRegularExpression] = {
        var result: [SyntaxLanguage: NSRegularExpression] = [:]
        if let slashSlash = try? NSRegularExpression(pattern: #"//.*$"#) {
            result[.swift] = slashSlash
            result[.typescript] = slashSlash
        }
        if let hash = try? NSRegularExpression(pattern: #"#.*$"#) {
            result[.python] = hash
            result[.shell] = hash
            result[.yaml] = hash
        }
        return result
    }()

    private static func commentMatches(_ line: String, language: SyntaxLanguage) -> [NSRange] {
        guard let pattern = commentPatterns[language] else { return [] }
        let nsLine = line as NSString
        return pattern.matches(in: line, range: NSRange(location: 0, length: nsLine.length)).map(\.range)
    }

    private static let numberPattern = try? NSRegularExpression(pattern: #"\b\d+\.?\d*\b"#)

    private static func numberMatches(_ line: String) -> [NSRange] {
        guard let numberPattern else { return [] }
        let nsLine = line as NSString
        return numberPattern.matches(in: line, range: NSRange(location: 0, length: nsLine.length)).map(\.range)
    }

    /// A capitalized identifier is treated as a type reference -- a cheap,
    /// convention-based heuristic (Swift/TS both capitalize type names by
    /// convention) rather than real symbol resolution, which a per-line
    /// regex pass has no way to do.
    private static let typePattern = try? NSRegularExpression(pattern: #"\b[A-Z][A-Za-z0-9_]*\b"#)

    private static func typeMatches(_ line: String, language: SyntaxLanguage) -> [NSRange] {
        guard language == .swift || language == .typescript, let typePattern else { return [] }
        let nsLine = line as NSString
        return typePattern.matches(in: line, range: NSRange(location: 0, length: nsLine.length)).map(\.range)
    }
}
