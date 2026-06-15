//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class BlockParserTests: XCTestCase {
    func test_paragraphWithBoldAndExtension() {
        let blocks = BlockParser.document("Valve **finally** shipped ==SteamOS==")
        XCTAssertEqual(blocks, [
            .paragraph([
                .text("Valve "),
                .strong([.text("finally")]),
                .text(" shipped "),
                .highlight([.text("SteamOS")]),
            ]),
        ])
    }

    func test_headings() {
        XCTAssertEqual(BlockParser.document("# Title"), [.heading(level: 1, [.text("Title")])])
        XCTAssertEqual(BlockParser.document("### Topic"), [.heading(level: 3, [.text("Topic")])])
    }

    func test_thematicBreak() {
        XCTAssertEqual(BlockParser.document("---"), [.thematicBreak])
    }

    func test_codeBlock() {
        let blocks = BlockParser.document("```bash\necho hi\n```")
        XCTAssertEqual(blocks, [.codeBlock(language: "bash", code: "echo hi")])
    }

    func test_orderedListWithStart() {
        let blocks = BlockParser.document("3. first\n4. second")
        XCTAssertEqual(blocks, [
            .orderedList(start: 3, [
                MarkdownListItem(blocks: [.paragraph([.text("first")])]),
                MarkdownListItem(blocks: [.paragraph([.text("second")])]),
            ]),
        ])
    }

    func test_nestedUnorderedList() {
        let blocks = BlockParser.document("- a\n    - b")
        XCTAssertEqual(blocks, [
            .unorderedList([
                MarkdownListItem(blocks: [
                    .paragraph([.text("a")]),
                    .unorderedList([MarkdownListItem(blocks: [.paragraph([.text("b")])])]),
                ]),
            ]),
        ])
    }

    func test_nestedBlockQuote() {
        let blocks = BlockParser.document("> outer\n>\n> > inner")
        XCTAssertEqual(blocks, [
            .blockQuote([
                .paragraph([.text("outer")]),
                .blockQuote([.paragraph([.text("inner")])]),
            ]),
        ])
    }

    func test_table() {
        let source = """
            | Sub | OK |
            |:---|---:|
            | Suspend | yes |
            """
        XCTAssertEqual(BlockParser.document(source), [
            .table(MarkdownTable(
                alignments: [.left, .right],
                head: [[.text("Sub")], [.text("OK")]],
                rows: [[[.text("Suspend")], [.text("yes")]]]
            )),
        ])
    }

    func test_standaloneImage() throws {
        let blocks = BlockParser.document("![a cat](https://x/cat.jpg)")
        XCTAssertEqual(blocks, try [.image(MarkdownImage(url: XCTUnwrap(URL(string: "https://x/cat.jpg")), altText: "a cat"))])
    }

    func test_standaloneVideoLinkBecomesVideoBlock() throws {
        let blocks = BlockParser.document("![clip](https://x/clip.mp4)")
        XCTAssertEqual(blocks, try [.video(url: XCTUnwrap(URL(string: "https://x/clip.mp4")))])
    }
}
