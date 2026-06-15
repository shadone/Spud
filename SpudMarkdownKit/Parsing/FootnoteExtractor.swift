//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Lifts `[^label]: text` footnote definitions out of the source. References
/// (`[^label]`) are left in place for the inline lexer. Single-line definitions
/// only (Phase 1).
enum FootnoteExtractor {
    struct Definition: Equatable { var label: String
        var text: String
    }

    struct Result { var source: String
        var definitions: [Definition]
    }

    static func extract(_ source: String) -> Result {
        var definitions: [Definition] = []
        var kept: [Substring] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            if let match = line.wholeMatch(of: /\[\^([\w-]+)\]:\s?(.*)/) {
                definitions.append(Definition(label: String(match.1), text: String(match.2)))
            } else {
                kept.append(line)
            }
        }
        return Result(source: kept.joined(separator: "\n"), definitions: definitions)
    }
}
