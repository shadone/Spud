//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Protects `^x^` superscript and `~x~` subscript from swift-markdown (whose
/// strikethrough extension can consume single tildes) by replacing them with
/// PUA-wrapped sentinels before parsing. `InlineLexer` restores them.
enum SubSupPreprocessor {
    static func protectText(_ source: String) -> String {
        var s = source
        s = s.replacing(/\^([^\^\s]+)\^/) { "\u{E010}sup:\($0.1)\u{E011}" }
        // Match `~content~` where the tilde on each side is NOT doubled.
        // Pattern: a single `~` not preceded by another `~` (handled by
        // requiring `[^~]` or start-of-string via the character class approach),
        // then non-whitespace non-tilde content, then a single `~` not followed
        // by another `~`. Swift regex has no lookbehind, so we capture the
        // preceding character and only replace when it is not `~`.
        s = replaceSingleTildes(in: s)
        return s
    }

    private static func replaceSingleTildes(in source: String) -> String {
        // Walk the string and replace ~content~ only when the tilde is not
        // adjacent to another tilde (i.e. not part of ~~strikethrough~~).
        var result = ""
        var index = source.startIndex
        while index < source.endIndex {
            let rest = source[index...]
            // Try to match `~content~` where this `~` is not preceded by `~`
            // and the closing `~` is not followed by `~`.
            if source[index] == "~" {
                let prevIsTilde = index > source.startIndex && source[source.index(before: index)] == "~"
                if !prevIsTilde,
                   let m = rest.prefixMatch(of: /~([^~\s]+)~/)
                {
                    // Verify the char after the match is not `~` (avoids ~~~x~~~).
                    let afterMatch = m.range.upperBound
                    let nextIsTilde = afterMatch < source.endIndex && source[afterMatch] == "~"
                    if !nextIsTilde {
                        result += "\u{E010}sub:\(m.output.1)\u{E011}"
                        index = afterMatch
                        continue
                    }
                }
            }
            result.append(source[index])
            index = source.index(after: index)
        }
        return result
    }
}
