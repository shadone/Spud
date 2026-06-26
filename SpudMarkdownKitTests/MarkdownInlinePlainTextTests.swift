//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class MarkdownInlinePlainTextTests: XCTestCase {
    func test_plainText_flattensTextAndEmphasis() {
        let inlines: [MarkdownInline] = [.text("Foo "), .strong([.text("bar")])]
        XCTAssertEqual(inlines.plainText, "Foo bar")
    }

    func test_plainText_code_and_mentions() {
        XCTAssertEqual([MarkdownInline.code("ls")].plainText, "ls")
        XCTAssertEqual([MarkdownInline.mention(name: "alice", instance: "lemmy.world")].plainText, "alice@lemmy.world")
        XCTAssertEqual([MarkdownInline.community(name: "tech", instance: "beehaw.org")].plainText, "tech@beehaw.org")
    }

    func test_plainText_link_usesItsOwnText() throws {
        let link = try MarkdownInline.link(text: [.text("Foobar")], url: XCTUnwrap(URL(string: "https://example.com")))
        XCTAssertEqual([link].plainText, "Foobar")
    }
}
