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
        var output: [String] = []
        var spoilers: [String: Spoiler] = [:]
        var nextID = 0

        var index = 0
        while index < lines.count {
            let line = lines[index]
            if let title = openingTitle(line) {
                var inner: [String] = []
                var depth = 1
                index += 1
                while index < lines.count {
                    let current = lines[index]
                    if openingTitle(current) != nil {
                        depth += 1
                        inner.append(current)
                    } else if isClosingFence(current) {
                        depth -= 1
                        if depth == 0 { break }
                        inner.append(current)
                    } else {
                        inner.append(current)
                    }
                    index += 1
                }
                let id = String(nextID)
                nextID += 1
                spoilers[id] = Spoiler(title: title, inner: inner.joined(separator: "\n"))
                output.append("")
                output.append(sentinel(for: id))
                output.append("")
            } else {
                output.append(line)
            }
            index += 1
        }

        return Result(source: output.joined(separator: "\n"), spoilers: spoilers)
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
