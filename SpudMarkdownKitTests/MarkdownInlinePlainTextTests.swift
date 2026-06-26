//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudMarkdownKit

struct MarkdownInlinePlainTextTests {
    @Test
    func plainText_flattensTextAndEmphasis() {
        let inlines: [MarkdownInline] = [.text("Foo "), .strong([.text("bar")])]
        #expect(inlines.plainText == "Foo bar")
    }

    @Test
    func plainText_code_and_mentions() {
        #expect([MarkdownInline.code("ls")].plainText == "ls")
        #expect([MarkdownInline.mention(name: "alice", instance: "lemmy.world")].plainText == "alice@lemmy.world")
        #expect([MarkdownInline.community(name: "tech", instance: "beehaw.org")].plainText == "tech@beehaw.org")
    }

    @Test
    func plainText_link_usesItsOwnText() throws {
        let link = try MarkdownInline.link(text: [.text("Foobar")], url: #require(URL(string: "https://example.com")))
        #expect([link].plainText == "Foobar")
    }
}
