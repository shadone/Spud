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

        if let m = rest.prefixMatch(of: Pattern.superscriptSentinel) {
            return (.superscript(parse(String(m.output.1))), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: Pattern.subscriptSentinel) {
            return (.subscript(parse(String(m.output.1))), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: Pattern.footnoteReference) {
            return (.footnoteReference(String(m.output.1)), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: Pattern.highlight) {
            return (.highlight(parse(String(m.output.1))), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: Pattern.customEmoji) {
            return (.customEmoji(shortcode: String(m.output.1)), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: Pattern.emojiShortcode) {
            let name = String(m.output.1)
            if let scalar = Emoji.map[name] {
                return (.emoji(scalar), count(m.range.upperBound))
            }
            // Unknown shortcode: emit the whole `:name:` token literally and
            // consume it, so its trailing colon can't open the next emoji.
            return (.text(String(rest[m.range])), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: Pattern.caretSuperscript) {
            return (.superscript(parse(String(m.output.1))), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: Pattern.tildeSubscript) {
            return (.subscript(parse(String(m.output.1))), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: Pattern.community) {
            return (.community(name: String(m.output.1), instance: String(m.output.2)), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: Pattern.mention) {
            return (.mention(name: String(m.output.1), instance: String(m.output.2)), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: Pattern.httpURL) {
            let trimmed = trimAutolinkTrailing(m.output)
            let raw = String(trimmed)
            if let url = URL(string: raw) {
                return (.link(text: [.text(raw)], url: url), trimmed.count)
            }
            return (.text(raw), trimmed.count)
        }
        if let m = rest.prefixMatch(of: Pattern.wwwURL) {
            let trimmed = trimAutolinkTrailing(m.output)
            let raw = String(trimmed)
            if let url = URL(string: "https://\(raw)") {
                return (.link(text: [.text(raw)], url: url), trimmed.count)
            }
            return (.text(raw), trimmed.count)
        }
        return nil
    }

    /// Applies the GFM autolink trailing-character rules to a raw autolinked URL
    /// match. The autolink regexes greedily grab every non-space, non-`<`
    /// character (so a balanced `…/Foo_(bar)` stays whole); this trims what should
    /// not belong to the URL:
    ///
    /// 1. Trailing sentence punctuation (`.,;:!?'"` and `>`) is dropped, so
    ///    `see https://example.com.` links only `https://example.com`.
    /// 2. An unbalanced trailing `)` is dropped — while the match ends in `)` and
    ///    it contains more `)` than `(`, peel the last `)` off. This keeps a link
    ///    inside parentheses tidy (`(see https://example.com)` -> the `)` is not
    ///    part of the link) while preserving a balanced Wikipedia-style
    ///    `…/Foo_(bar)` or nested `…/Foo_(bar_(baz))`.
    ///
    /// The two rules alternate in one loop because trimming one can uncover the
    /// other (e.g. `…(x).` drops `.` then `)`). The dropped suffix is left in the
    /// input to re-enter the lexer as literal text: `match` reports only
    /// `trimmed.count` Characters consumed.
    private static func trimAutolinkTrailing(_ raw: Substring) -> Substring {
        var end = raw.endIndex
        loop: while end > raw.startIndex {
            let lastIndex = raw.index(before: end)
            switch raw[lastIndex] {
            case ".", ",", ";", ":", "!", "?", "'", "\"", ">":
                end = lastIndex
            case ")":
                let slice = raw[raw.startIndex..<end]
                var opens = 0
                var closes = 0
                for character in slice {
                    if character == "(" { opens += 1 }
                    else if character == ")" { closes += 1 }
                }
                if closes > opens {
                    end = lastIndex
                } else {
                    break loop
                }
            default:
                break loop
            }
        }
        return raw[raw.startIndex..<end]
    }

    /// Compile-once regexes for the inline extension rules.
    ///
    /// `match` runs once per Character of every text node, so the regexes it
    /// tries must be built ahead of time, not from regex *literals* inside the
    /// loop: each evaluation of a `/.../ ` literal compiles a fresh `Regex`
    /// program, which turned a long post body into (characters x rules) regex
    /// compilations on the main thread — multiple seconds for a wall of text.
    /// Hoisting them here makes each rule compile exactly once.
    ///
    /// `nonisolated(unsafe)` is safe: `Regex` matching is a read-only operation
    /// over an immutable compiled program (the regex value is never mutated), so
    /// sharing one instance across the main actor and the off-main pre-warm pool
    /// has no data race. `Regex` itself just isn't marked `Sendable`.
    private enum Pattern {
        nonisolated(unsafe) static let superscriptSentinel = /\u{E010}sup:([^\u{E011}]+)\u{E011}/
        nonisolated(unsafe) static let subscriptSentinel = /\u{E010}sub:([^\u{E011}]+)\u{E011}/
        nonisolated(unsafe) static let footnoteReference = /\[\^([\w-]+)\]/
        nonisolated(unsafe) static let highlight = /==([^=]+)==/
        nonisolated(unsafe) static let customEmoji = /::([a-zA-Z0-9_+\-]+)::/
        nonisolated(unsafe) static let emojiShortcode = /:([a-zA-Z0-9_+\-]+):/
        nonisolated(unsafe) static let caretSuperscript = /\^([^\^\s]+)\^/
        nonisolated(unsafe) static let tildeSubscript = /~([^~\s]+)~/
        nonisolated(unsafe) static let community = /!([a-zA-Z0-9_]+)@([a-zA-Z0-9.\-]+)/
        nonisolated(unsafe) static let mention = /@([a-zA-Z0-9_]+)@([a-zA-Z0-9.\-]+)/
        // Grab the whole non-space run (parentheses included, so a balanced
        // `…/Foo_(bar)` stays intact); `trimAutolinkTrailing` then peels off
        // trailing sentence punctuation and any unbalanced `)` per the GFM rule.
        nonisolated(unsafe) static let httpURL = /https?:\/\/[^\s<]+/
        nonisolated(unsafe) static let wwwURL = /www\.[^\s<]+/
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
