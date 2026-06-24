//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Best-effort markdown-to-plain-text stripping for compact list previews.
public enum MarkdownPlainText {
    /// Strips markdown syntax from `markdown`, returning compact plain text for a
    /// one/two-line list preview. Pure string work — no markdown parse, no
    /// rendering — so it is safe to call on the scroll path. Best-effort: aims to
    /// remove the common syntax that would otherwise leak into the feed (headings,
    /// emphasis, links, list/quote markers), not to be a full CommonMark parser.
    /// It is heuristic: a stray single `*`/`_` between non-markdown tokens (e.g.
    /// `$5*10` math or prices) may be treated as emphasis, matching how a
    /// CommonMark renderer would also interpret them.
    public static func preview(from markdown: String) -> String {
        // A 2-line preview never needs the whole body; cap the input so the regex
        // passes stay cheap on the scroll path regardless of body length.
        let source = String(markdown.prefix(2000))

        let lines = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { stripBlockSyntax(from: String($0)) }

        let joined = lines.joined(separator: " ")
        let inlined = stripInlineSyntax(from: joined)

        return inlined
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Block-level (per line)

    /// Returns the line with leading block markers stripped, or `nil` when the
    /// whole line is structural (fence delimiter, thematic break, setext rule,
    /// bare spoiler close).
    private static func stripBlockSyntax(from line: String) -> String? {
        // Fenced-code delimiter line (```/~~~) — drop the delimiter, keep code.
        // CommonMark: any line starting with a 3+ backtick/tilde run is a fence
        // delimiter, so match the start (not the whole line) to also catch an
        // opening fence with an info string like ```swift.
        if line.range(of: #"^\s*(```+|~~~+)"#, options: .regularExpression) != nil {
            return nil
        }

        // Lemmy spoiler: opening line becomes its title; bare close is dropped.
        if let title = spoilerTitle(in: line) {
            return title
        }
        if line.range(of: #"^\s*:::\s*$"#, options: .regularExpression) != nil {
            return nil
        }

        // Thematic break (---, ***, ___).
        if line.range(of: #"^\s*([-*_])(?:\s*\1){2,}\s*$"#, options: .regularExpression) != nil {
            return nil
        }

        // Setext underline (=== or ---).
        if line.range(of: #"^\s*(=+|-+)\s*$"#, options: .regularExpression) != nil {
            return nil
        }

        var result = line

        // Leading blockquote prefix(es).
        result = replace(in: result, pattern: #"^\s*(?:>\s?)+"#, with: "")

        // Leading ATX heading prefix and trailing closing hashes.
        result = replace(in: result, pattern: #"^\s{0,3}#{1,6}\s+"#, with: "")
        result = replace(in: result, pattern: #"\s+#+\s*$"#, with: "")

        // Leading list markers (unordered or ordered).
        result = replace(in: result, pattern: #"^\s*[-*+]\s+"#, with: "")
        result = replace(in: result, pattern: #"^\s*\d+[.)]\s+"#, with: "")

        return result
    }

    // MARK: Inline

    private static func stripInlineSyntax(from text: String) -> String {
        var result = text

        // Images before links (image syntax is a superset of link syntax).
        result = replace(in: result, pattern: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1")
        result = replace(in: result, pattern: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1")
        result = replace(in: result, pattern: #"\[([^\]]+)\]\[[^\]]*\]"#, with: "$1")

        // Autolinks <http://...> keep the bare URL.
        result = replace(in: result, pattern: #"<(https?://[^>]+)>"#, with: "$1")

        // Emphasis / code — run twice to unwrap one nesting level (e.g. ***x***).
        for _ in 0..<2 {
            result = stripEmphasis(from: result)
        }

        // Unescape backslash-escaped punctuation.
        result = replace(
            in: result,
            pattern: #"\\([\\`*_{}\[\]()#+\-.!~>])"#,
            with: "$1"
        )

        return result
    }

    private static func stripEmphasis(from text: String) -> String {
        var result = text
        // A backslash-escaped opening delimiter (e.g. \*) is a literal, not
        // emphasis — guard each opener with (?<!\\) so the later unescape pass
        // turns it back into a plain character.
        result = replace(in: result, pattern: #"(?<!\\)\*\*([^*]+?)\*\*"#, with: "$1")
        // Double-underscore strong emphasis only at non-word boundaries
        // (intraword foo__bar__baz survives, mirroring the single-underscore guard).
        result = replace(in: result, pattern: #"(?<![\w\\])__([^_]+?)__(?!\w)"#, with: "$1")
        result = replace(in: result, pattern: #"(?<!\\)\*([^*]+?)\*"#, with: "$1")
        // Underscore emphasis only at non-word boundaries (snake_case survives).
        result = replace(in: result, pattern: #"(?<![\w\\])_([^_]+?)_(?![\w])"#, with: "$1")
        result = replace(in: result, pattern: #"(?<!\\)~~([^~]+?)~~"#, with: "$1")
        result = replace(in: result, pattern: #"(?<!\\)==([^=]+?)=="#, with: "$1")
        result = replace(in: result, pattern: #"(?<!\\)`([^`]+?)`"#, with: "$1")
        return result
    }

    // MARK: Regex helpers

    private static func replace(
        in text: String,
        pattern: String,
        with template: String
    ) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }

    /// Lemmy spoiler opening line: `::: spoiler <title>`. Compiled once — the
    /// pattern is a compile-time constant and `NSRegularExpression` is thread-safe
    /// for matching, so a `static let` is fine on the scroll path.
    private static let spoilerTitleRegex = try! NSRegularExpression(
        pattern: #"^\s*:::\s*spoiler\s*(.*)$"#
    )

    /// Returns the spoiler title captured by `spoilerTitleRegex`, or `nil` when
    /// `line` is not a spoiler opening line.
    private static func spoilerTitle(in line: String) -> String? {
        guard
            let match = spoilerTitleRegex.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
            ),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return String(line[range])
    }
}
