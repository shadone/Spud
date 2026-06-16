//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class InlineLexerTests: XCTestCase {
    func test_plainTextGetsSmartTypography() {
        XCTAssertEqual(InlineLexer.parse("a--b"), [.text("a\u{2013}b")])
    }

    func test_highlight() {
        XCTAssertEqual(InlineLexer.parse("see ==this=="), [.text("see "), .highlight([.text("this")])])
    }

    func test_superscriptAndSubscript() {
        XCTAssertEqual(InlineLexer.parse("E=mc^2^"), [.text("E=mc"), .superscript([.text("2")])])
        XCTAssertEqual(InlineLexer.parse("H~2~O"), [.text("H"), .subscript([.text("2")]), .text("O")])
    }

    func test_mentionAndCommunity() {
        XCTAssertEqual(
            InlineLexer.parse("ping @glidergun@lemmy.world in !linux_gaming@lemmy.world"),
            [
                .text("ping "),
                .mention(name: "glidergun", instance: "lemmy.world"),
                .text(" in "),
                .community(name: "linux_gaming", instance: "lemmy.world"),
            ]
        )
    }

    func test_footnoteReference() {
        XCTAssertEqual(InlineLexer.parse("welcome[^1]"), [.text("welcome"), .footnoteReference("1")])
    }

    func test_autolink() {
        let result = InlineLexer.parse("see https://lemmy.world/post/42 now")
        guard case let .link(text, url) = result[1] else { return XCTFail("expected link, got \(result)") }
        XCTAssertEqual(url, URL(string: "https://lemmy.world/post/42"))
        XCTAssertEqual(text, [.text("https://lemmy.world/post/42")])
    }

    func test_knownEmojiAndCustomEmoji() {
        XCTAssertEqual(InlineLexer.parse(":penguin:"), [.emoji("\u{1F427}")])
        XCTAssertEqual(InlineLexer.parse("::potato::"), [.customEmoji(shortcode: "potato")])
    }

    func test_unknownEmojiStaysLiteral() {
        XCTAssertEqual(InlineLexer.parse(":not_an_emoji:"), [.text(":not_an_emoji:")])
    }

    func test_unknownShortcodeDoesNotLeakIntoNextEmoji() {
        // ":foo:" is unknown -> stays literal; its trailing colon must NOT open
        // ":penguin:". Expect two literal text runs, no penguin emoji.
        XCTAssertEqual(
            InlineLexer.parse(":foo:penguin:"),
            [.text(":foo:"), .text("penguin:")]
        )
    }
}
