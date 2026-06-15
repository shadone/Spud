//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class MarkdownParserTests: XCTestCase {
    func test_spoilerBecomesSpoilerBlockWithParsedChildren() {
        let blocks = MarkdownParser.parse("::: spoiler Numbers\nLocked **60** fps.\n:::")
        XCTAssertEqual(blocks, [
            .spoiler(title: [.text("Numbers")], children: [
                .paragraph([.text("Locked "), .strong([.text("60")]), .text(" fps.")]),
            ]),
        ])
    }

    func test_footnotesAppendedAsBlock() {
        let blocks = MarkdownParser.parse("Thanks.[^1]\n\n[^1]: Over wired.")
        XCTAssertEqual(blocks, [
            .paragraph([.text("Thanks."), .footnoteReference("1")]),
            .footnotes([MarkdownFootnote(label: "1", content: [.text("Over wired.")])]),
        ])
    }

    func test_emptySourceProducesNoBlocks() {
        XCTAssertEqual(MarkdownParser.parse(""), [])
    }

    func test_plainParagraph() {
        XCTAssertEqual(MarkdownParser.parse("Hello world"), [.paragraph([.text("Hello world")])])
    }
}
