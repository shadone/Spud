//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudMarkdownKit

struct InlineLexerTests {
    @Test
    func plainTextGetsSmartTypography() {
        #expect(InlineLexer.parse("a--b") == [.text("a\u{2013}b")])
    }

    @Test
    func highlight() {
        #expect(InlineLexer.parse("see ==this==") == [.text("see "), .highlight([.text("this")])])
    }

    @Test
    func superscriptAndSubscript() {
        #expect(InlineLexer.parse("E=mc^2^") == [.text("E=mc"), .superscript([.text("2")])])
        #expect(InlineLexer.parse("H~2~O") == [.text("H"), .subscript([.text("2")]), .text("O")])
    }

    @Test
    func mentionAndCommunity() {
        #expect(
            InlineLexer.parse("ping @glidergun@lemmy.world in !linux_gaming@lemmy.world") ==
                [
                    .text("ping "),
                    .mention(name: "glidergun", instance: "lemmy.world"),
                    .text(" in "),
                    .community(name: "linux_gaming", instance: "lemmy.world"),
                ]
        )
    }

    @Test
    func footnoteReference() {
        #expect(InlineLexer.parse("welcome[^1]") == [.text("welcome"), .footnoteReference("1")])
    }

    @Test
    func autolink() {
        let result = InlineLexer.parse("see https://lemmy.world/post/42 now")
        guard case let .link(text, url) = result[1] else {
            Issue.record("expected link, got \(result)")
            return
        }
        #expect(url == URL(string: "https://lemmy.world/post/42"))
        #expect(text == [.text("https://lemmy.world/post/42")])
    }

    @Test
    func knownEmojiAndCustomEmoji() {
        #expect(InlineLexer.parse(":penguin:") == [.emoji("\u{1F427}")])
        #expect(InlineLexer.parse("::potato::") == [.customEmoji(shortcode: "potato")])
    }

    @Test
    func unknownEmojiStaysLiteral() {
        #expect(InlineLexer.parse(":not_an_emoji:") == [.text(":not_an_emoji:")])
    }

    @Test
    func unknownShortcodeDoesNotLeakIntoNextEmoji() {
        // ":foo:" is unknown -> stays literal; its trailing colon must NOT open
        // ":penguin:". Expect two literal text runs, no penguin emoji.
        #expect(
            InlineLexer.parse(":foo:penguin:") ==
                [.text(":foo:"), .text("penguin:")]
        )
    }

    /// Guards against re-inlining the extension-rule regexes (see `Pattern` in
    /// InlineLexer). `match` runs once per Character, so a regex *literal* in the
    /// loop recompiles per Character and a long body costs (chars x rules)
    /// compilations — multiple seconds for a wall of text, on the main thread.
    /// With the regexes compiled once this body lexes in tens of milliseconds;
    /// the 2s ceiling is ~30x the healthy time but still well under the seconds
    /// the regression took, so it catches the bug without flaking on slow CI.
    @Test
    func longBodyLexesWithoutPerCharacterRegexRecompilation() {
        let paragraph = """
            This is a fairly normal paragraph of prose that someone might write in a \
            long Lemmy post. It has punctuation, numbers like 42 and 2026, the odd \
            link such as https://example.com/some/path?q=1 and a mention of \
            @someone@example.com once in a while, but mostly just ordinary words.
            """
        var body = ""
        while body.count < 20000 {
            body += paragraph + "\n\n"
        }

        let start = Date()
        _ = InlineLexer.parse(body)
        let elapsed = Date().timeIntervalSince(start)

        #expect(
            elapsed < 2.0,
            "Lexing a \(body.count)-char body took \(elapsed)s; the per-Character regex recompilation regression is likely back."
        )
    }
}
