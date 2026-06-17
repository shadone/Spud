//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Lifts `::: spoiler <title>` ... `:::` containers out of the source, replacing
/// each with a sentinel paragraph that swift-markdown parses as plain text.
/// `MarkdownParser` swaps the sentinel back for a real spoiler block, recursively
/// parsing the captured inner source.
enum SpoilerPreprocessor {
    struct Spoiler { var title: String
        var inner: String
    }

    struct Result { var source: String
        var spoilers: [String: Spoiler]
    }

    /// The standalone token written into the cleaned source for spoiler `id`.
    /// Wrapped in Private-Use-Area scalars so it can't collide with content.
    static func sentinel(for id: String) -> String {
        "\u{E000}spoiler:\(id)\u{E001}"
    }

    static func preprocess(_ source: String) -> Result {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let isCode = MarkdownFenceScanner.codeLineFlags(lines)
        var output: [String] = []
        var spoilers: [String: Spoiler] = [:]
        var nextID = 0

        var index = 0
        while index < lines.count {
            let line = lines[index]
            if !isCode[index], let title = openingTitle(line) {
                // Preserve the opening fence's indentation so the sentinel stays in
                // its container (e.g. a list item) instead of floating to column 0.
                let indent = String(line.prefix(while: { $0 == " " }))
                var inner: [String] = []
                var depth = 1
                index += 1
                while index < lines.count {
                    let current = lines[index]
                    if !isCode[index], openingTitle(current) != nil {
                        depth += 1
                        inner.append(stripIndent(current, upTo: indent.count))
                    } else if !isCode[index], isClosingFence(current) {
                        depth -= 1
                        if depth == 0 { break }
                        inner.append(stripIndent(current, upTo: indent.count))
                    } else {
                        inner.append(stripIndent(current, upTo: indent.count))
                    }
                    index += 1
                }
                let id = String(nextID)
                nextID += 1
                spoilers[id] = Spoiler(title: title, inner: inner.joined(separator: "\n"))
                output.append("")
                output.append(indent + sentinel(for: id))
                output.append("")
            } else {
                output.append(line)
            }
            index += 1
        }

        return Result(source: output.joined(separator: "\n"), spoilers: spoilers)
    }

    /// Removes up to `count` leading spaces, so inner content captured from an
    /// indented spoiler re-parses at column 0 (otherwise deep indentation would
    /// be misread as an indented code block).
    private static func stripIndent(_ line: String, upTo count: Int) -> String {
        var removed = 0
        var index = line.startIndex
        while removed < count, index < line.endIndex, line[index] == " " {
            index = line.index(after: index)
            removed += 1
        }
        return String(line[index...])
    }

    /// The title if `line` opens a spoiler (`::: spoiler [title]`), else nil.
    private static func openingTitle(_ line: String) -> String? {
        guard let match = line.wholeMatch(of: /\s*:::\s*spoiler\s?(.*)/) else { return nil }
        return String(match.1).trimmingCharacters(in: .whitespaces)
    }

    private static func isClosingFence(_ line: String) -> Bool {
        line.wholeMatch(of: /\s*:::\s*/) != nil
    }
}
