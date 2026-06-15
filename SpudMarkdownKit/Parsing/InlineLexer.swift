//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Lexes the inline extensions Lemmy adds on top of CommonMark, operating on the
/// plain string of one swift-markdown `Text` node (structural inlines like bold,
/// links, and `~~strike~~` are already consumed by swift-markdown).
enum InlineLexer {
    static func parse(_ string: String) -> [MarkdownInline] {
        var out: [MarkdownInline] = []
        var buffer = ""

        func flushText() {
            if !buffer.isEmpty {
                out.append(.text(SmartTypography.apply(buffer)))
                buffer = ""
            }
        }

        var index = string.startIndex
        while index < string.endIndex {
            let rest = string[index...]
            if let (inline, consumed) = match(rest) {
                flushText()
                out.append(inline)
                index = string.index(index, offsetBy: consumed)
            } else {
                buffer.append(string[index])
                index = string.index(after: index)
            }
        }
        flushText()
        return out
    }

    /// Tries each extension rule, anchored at the start of `rest`. Returns the
    /// produced inline and the number of Characters consumed.
    private static func match(_ rest: Substring) -> (MarkdownInline, Int)? {
        func count(_ upper: Substring.Index) -> Int {
            rest.distance(from: rest.startIndex, to: upper)
        }

        if let m = rest.prefixMatch(of: /\[\^([\w-]+)\]/) {
            return (.footnoteReference(String(m.output.1)), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: /==([^=]+)==/) {
            return (.highlight(parse(String(m.output.1))), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: /::([a-zA-Z0-9_+\-]+)::/) {
            return (.customEmoji(shortcode: String(m.output.1)), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: /:([a-zA-Z0-9_+\-]+):/) {
            let name = String(m.output.1)
            if let scalar = Emoji.map[name] {
                return (.emoji(scalar), count(m.range.upperBound))
            }
            return nil // unknown shortcode -> fall through to literal text
        }
        if let m = rest.prefixMatch(of: /\^([^\^\s]+)\^/) {
            return (.superscript(parse(String(m.output.1))), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: /~([^~\s]+)~/) {
            return (.subscript(parse(String(m.output.1))), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: /!([a-zA-Z0-9_]+)@([a-zA-Z0-9.\-]+)/) {
            return (.community(name: String(m.output.1), instance: String(m.output.2)), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: /@([a-zA-Z0-9_]+)@([a-zA-Z0-9.\-]+)/) {
            return (.mention(name: String(m.output.1), instance: String(m.output.2)), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: /https?:\/\/[^\s)<]+[^\s).,;:!?'"<]/) {
            let raw = String(m.output)
            if let url = URL(string: raw) {
                return (.link(text: [.text(raw)], url: url), count(m.range.upperBound))
            }
            return nil
        }
        if let m = rest.prefixMatch(of: /www\.[^\s)<]+[^\s).,;:!?'"<]/) {
            let raw = String(m.output)
            if let url = URL(string: "https://\(raw)") {
                return (.link(text: [.text(raw)], url: url), count(m.range.upperBound))
            }
            return nil
        }
        return nil
    }
}

/// Minimal `:shortcode:` -> unicode table. Unknown shortcodes render literally.
enum Emoji {
    static let map: [String: String] = [
        "smile": "\u{1F604}", "grinning": "\u{1F600}", "joy": "\u{1F602}", "wave": "\u{1F44B}",
        "rocket": "\u{1F680}", "tada": "\u{1F389}", "fire": "\u{1F525}", "eyes": "\u{1F440}",
        "heart": "\u{2764}\u{FE0F}", "+1": "\u{1F44D}", "-1": "\u{1F44E}", "thinking": "\u{1F914}",
        "sob": "\u{1F62D}", "sweat_smile": "\u{1F605}", "sparkles": "\u{2728}", "penguin": "\u{1F427}",
        "bulb": "\u{1F4A1}", "warning": "\u{26A0}\u{FE0F}", "white_check_mark": "\u{2705}",
        "potato": "\u{1F954}", "robot": "\u{1F916}", "zap": "\u{26A1}", "tv": "\u{1F4FA}",
        "sound": "\u{1F50A}",
    ]
}
