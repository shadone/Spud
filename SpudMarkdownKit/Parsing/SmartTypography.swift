//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// markdown-it `typographer:true` equivalent: smart quotes, dashes, ellipsis,
/// and the (c)/(tm)/(r) symbols. Applied to plain text runs during lexing.
enum SmartTypography {
    static func apply(_ input: String) -> String {
        var s = input
        s = s.replacingOccurrences(of: "(c)", with: "\u{00A9}", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "(tm)", with: "\u{2122}", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "(r)", with: "\u{00AE}", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "---", with: "\u{2014}")
        s = s.replacingOccurrences(of: "--", with: "\u{2013}")
        s = s.replacingOccurrences(of: "...", with: "\u{2026}")
        // Paired double quotes -> curly
        s = s.replacing(/"([^"]*)"/) { match in "\u{201C}\(match.1)\u{201D}" }
        // Opening single quote after start / whitespace / opening bracket
        s = s.replacing(/(^|[\s(\[{])'/) { match in "\(match.1)\u{2018}" }
        // Any remaining straight apostrophe -> right single quote
        s = s.replacingOccurrences(of: "'", with: "\u{2019}")
        return s
    }
}
