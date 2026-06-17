//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Identifies which lines of a markdown source sit inside a fenced code block
/// (``` or ~~~). The raw-source preprocessors (footnote / spoiler / sub-sup) run
/// before swift-markdown sees the document, so they consult this to leave code
/// fences untouched -- a `[^1]:`, `::: spoiler`, or `^x^` token inside a fence is
/// literal code, not markup.
enum MarkdownFenceScanner {
    /// For each line in `lines`, whether it belongs to a fenced code block. The
    /// opening and closing fence delimiter lines are themselves reported as code.
    static func codeLineFlags(_ lines: [String]) -> [Bool] {
        var flags = [Bool](repeating: false, count: lines.count)
        var open: (marker: Character, count: Int)?
        for (index, line) in lines.enumerated() {
            if let fence = open {
                flags[index] = true
                if isClosingFence(line, marker: fence.marker, count: fence.count) {
                    open = nil
                }
            } else if let opened = openingFence(line) {
                flags[index] = true
                open = opened
            }
        }
        return flags
    }

    /// Count of leading spaces, capped for the `<= 3` CommonMark fence indent rule.
    private static func leadingSpaces(_ line: Substring) -> Int {
        line.prefix(while: { $0 == " " }).count
    }

    /// The (marker, length) if `line` opens a fence (3+ backticks/tildes, indented
    /// at most 3 spaces; a backtick info string may not itself contain a backtick).
    private static func openingFence(_ line: String) -> (marker: Character, count: Int)? {
        let full = Substring(line)
        guard leadingSpaces(full) <= 3 else { return nil }
        let body = full.drop(while: { $0 == " " })
        guard let marker = body.first, marker == "`" || marker == "~" else { return nil }
        let count = body.prefix(while: { $0 == marker }).count
        guard count >= 3 else { return nil }
        let info = body.dropFirst(count)
        if marker == "`", info.contains("`") { return nil }
        return (marker, count)
    }

    /// Whether `line` closes a fence opened with `count` of `marker`: at least as
    /// many of the same marker, indented <= 3 spaces, followed only by whitespace.
    private static func isClosingFence(_ line: String, marker: Character, count: Int) -> Bool {
        let full = Substring(line)
        guard leadingSpaces(full) <= 3 else { return false }
        let body = full.drop(while: { $0 == " " })
        let run = body.prefix(while: { $0 == marker }).count
        guard run >= count else { return false }
        return body.dropFirst(run).allSatisfy { $0 == " " || $0 == "\t" }
    }
}
