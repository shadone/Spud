//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudMarkdownKit

struct MarkdownParserTests {
    @Test
    func spoilerBecomesSpoilerBlockWithParsedChildren() {
        let blocks = MarkdownParser.parse("::: spoiler Numbers\nLocked **60** fps.\n:::")
        #expect(blocks == [
            .spoiler(title: [.text("Numbers")], children: [
                .paragraph([.text("Locked "), .strong([.text("60")]), .text(" fps.")]),
            ]),
        ])
    }

    @Test
    func footnotesAppendedAsBlock() {
        let blocks = MarkdownParser.parse("Thanks.[^1]\n\n[^1]: Over wired.")
        #expect(blocks == [
            .paragraph([.text("Thanks."), .footnoteReference("1")]),
            .footnotes([MarkdownFootnote(label: "1", content: [.text("Over wired.")])]),
        ])
    }

    @Test
    func emptySourceProducesNoBlocks() {
        #expect(MarkdownParser.parse("") == [])
    }

    @Test
    func plainParagraph() {
        #expect(MarkdownParser.parse("Hello world") == [.paragraph([.text("Hello world")])])
    }

    @Test
    func spoilerInsideListItemBecomesSpoilerBlock() {
        let source = "- first\n- second\n\n  ::: spoiler More\n  details\n  :::"
        let blocks = MarkdownParser.parse(source)
        let listItemSpoiler = blocks.contains { block in
            guard case let .unorderedList(items) = block else { return false }
            return items.contains { item in
                item.blocks.contains { if case .spoiler = $0 { return true }
                    return false
                }
            }
        }
        #expect(listItemSpoiler, "spoiler should be reinjected inside the list item, got: \(blocks)")
        #expect(!("\(blocks)".contains("spoiler:0")), "sentinel leaked as literal text: \(blocks)")
    }

    @Test
    func fencedCodeKeepsMarkdownTokensLiteral() {
        let source = "```\n[^1]: not a note\n::: spoiler x\nH~2~O x^2^\n```"
        #expect(MarkdownParser.parse(source) == [
            .codeBlock(language: nil, code: "[^1]: not a note\n::: spoiler x\nH~2~O x^2^"),
        ])
    }

    @Test
    func kitchenSinkStructuralShape() {
        let blocks = MarkdownParser.parse(KitchenSink.post)

        func kind(_ block: MarkdownBlock) -> String {
            switch block {
            case .paragraph: return "paragraph"
            case .heading: return "heading"
            case .unorderedList: return "unorderedList"
            case .orderedList: return "orderedList"
            case .blockQuote: return "blockQuote"
            case .codeBlock: return "codeBlock"
            case .table: return "table"
            case .image: return "image"
            case .audio: return "audio"
            case .video: return "video"
            case .spoiler: return "spoiler"
            case .footnotes: return "footnotes"
            case .thematicBreak: return "thematicBreak"
            }
        }
        let kinds = blocks.map(kind)

        for expected in [
            "paragraph",
            "heading",
            "unorderedList",
            "orderedList",
            "table",
            "codeBlock",
            "blockQuote",
            "image",
            "video",
            "spoiler",
            "thematicBreak",
            "footnotes",
        ] {
            #expect(kinds.contains(expected), "missing \(expected) in \(kinds)")
        }

        guard case let .footnotes(notes) = blocks.last else {
            Issue.record("last block should be footnotes, got \(kinds)")
            return
        }
        #expect(notes.map(\.label) == ["1"])

        #expect(blocks.contains { if case .video = $0 { return true }
            return false
        })

        let emptyBodySpoiler = blocks.contains {
            if case let .spoiler(_, children) = $0 { return children.isEmpty }
            return false
        }
        #expect(emptyBodySpoiler, "body-less spoiler should be present")
    }

    @Test
    func kitchenSinkSubscriptSurvives() {
        let blocks = MarkdownParser.parse(KitchenSink.post)
        let hasSubscript = blocks.contains { block in
            if case let .paragraph(inlines) = block { return containsSubscript(inlines) }
            return false
        }
        #expect(hasSubscript, "H~2~O subscript was lost (swift-markdown likely ate single tildes)")
    }

    private func containsSubscript(_ inlines: [MarkdownInline]) -> Bool {
        for inline in inlines {
            switch inline {
            case .subscript: return true
            case let .strong(children), let .emphasis(children), let .highlight(children),
                 let .superscript(children), let .strikethrough(children):
                if containsSubscript(children) { return true }
            default: break
            }
        }
        return false
    }
}
