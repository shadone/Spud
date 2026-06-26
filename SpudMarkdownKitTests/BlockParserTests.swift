//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudMarkdownKit

struct BlockParserTests {
    @Test
    func paragraphWithBoldAndExtension() {
        let blocks = BlockParser.document("Valve **finally** shipped ==SteamOS==")
        #expect(blocks == [
            .paragraph([
                .text("Valve "),
                .strong([.text("finally")]),
                .text(" shipped "),
                .highlight([.text("SteamOS")]),
            ]),
        ])
    }

    @Test
    func headings() {
        #expect(BlockParser.document("# Title") == [.heading(level: 1, [.text("Title")])])
        #expect(BlockParser.document("### Topic") == [.heading(level: 3, [.text("Topic")])])
    }

    @Test
    func thematicBreak() {
        #expect(BlockParser.document("---") == [.thematicBreak])
    }

    @Test
    func codeBlock() {
        let blocks = BlockParser.document("```bash\necho hi\n```")
        #expect(blocks == [.codeBlock(language: "bash", code: "echo hi")])
    }

    @Test
    func orderedListWithStart() {
        let blocks = BlockParser.document("3. first\n4. second")
        #expect(blocks == [
            .orderedList(start: 3, [
                MarkdownListItem(blocks: [.paragraph([.text("first")])]),
                MarkdownListItem(blocks: [.paragraph([.text("second")])]),
            ]),
        ])
    }

    @Test
    func nestedUnorderedList() {
        let blocks = BlockParser.document("- a\n    - b")
        #expect(blocks == [
            .unorderedList([
                MarkdownListItem(blocks: [
                    .paragraph([.text("a")]),
                    .unorderedList([MarkdownListItem(blocks: [.paragraph([.text("b")])])]),
                ]),
            ]),
        ])
    }

    @Test
    func nestedBlockQuote() {
        let blocks = BlockParser.document("> outer\n>\n> > inner")
        #expect(blocks == [
            .blockQuote([
                .paragraph([.text("outer")]),
                .blockQuote([.paragraph([.text("inner")])]),
            ]),
        ])
    }

    @Test
    func table() {
        let source = """
            | Sub | OK |
            |:---|---:|
            | Suspend | yes |
            """
        #expect(BlockParser.document(source) == [
            .table(MarkdownTable(
                alignments: [.left, .right],
                head: [[.text("Sub")], [.text("OK")]],
                rows: [[[.text("Suspend")], [.text("yes")]]]
            )),
        ])
    }

    @Test
    func standaloneImage() throws {
        let blocks = BlockParser.document("![a cat](https://x/cat.jpg)")
        let url = try #require(URL(string: "https://x/cat.jpg"))
        #expect(blocks == [.image(MarkdownImage(url: url, altText: "a cat"))])
    }

    @Test
    func standaloneVideoLinkBecomesVideoBlock() throws {
        let blocks = BlockParser.document("![clip](https://x/clip.mp4)")
        let url = try #require(URL(string: "https://x/clip.mp4"))
        #expect(blocks == [.video(url: url)])
    }
}
