//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudMarkdownKit

struct EdgeCaseParsingTests {
    // MARK: Case 1 — Raw HTML is literal text, never parsed into emphasis/strong

    @Test
    func rawHtmlInlineTagsBecomeLiteralText() {
        // swift-markdown emits InlineHTML nodes for angle-bracket tags;
        // BlockParser.convertInline returns [.text(rawHTML)] for them.
        let blocks = MarkdownParser.parse("a <b>x</b> c")
        guard case let .paragraph(inlines) = blocks.first else {
            Issue.record("expected paragraph, got \(blocks)")
            return
        }
        // Must not contain any .strong or .emphasis — tags are literal text.
        for inline in inlines {
            if case .strong = inline { Issue.record("raw HTML tag was parsed into .strong") }
            if case .emphasis = inline { Issue.record("raw HTML tag was parsed into .emphasis") }
        }
        // The angle-bracket content must appear as literal text somewhere.
        let allText = inlines.compactMap { if case let .text(t) = $0 { return t } else { return nil } }
        #expect(allText.joined().contains("<b>"), "expected '<b>' as literal text in \(inlines)")
        #expect(allText.joined().contains("</b>"), "expected '</b>' as literal text in \(inlines)")
    }

    @Test
    func rawHtmlBlockDoesNotCrashAndIsDropped() {
        // BlockParser.convertBlock drops HTMLBlock (returns nil in the default branch).
        // The result may be empty or (if swift-markdown folds it into a paragraph) contain
        // literal text — but it must never crash and must never synthesize emphasis/strong.
        let blocks = MarkdownParser.parse("<div>raw</div>")
        /// Must not crash (the call above already proves that).
        /// Must not contain any .strong or .emphasis.
        func hasEmphasisOrStrong(_ block: MarkdownBlock) -> Bool {
            func check(_ inlines: [MarkdownInline]) -> Bool {
                inlines.contains {
                    switch $0 {
                    case .strong, .emphasis: return true
                    default: return false
                    }
                }
            }
            switch block {
            case let .paragraph(inlines): return check(inlines)
            default: return false
            }
        }
        #expect(!(blocks.contains { hasEmphasisOrStrong($0) }), "raw HTML block must not produce emphasis/strong: \(blocks)")
        #expect(blocks.isEmpty, "a block-level HTML element must be dropped entirely: \(blocks)")
    }

    // MARK: Case 2 — Orphaned footnote reference (ref, no definition)

    @Test
    func orphanedFootnoteReferenceNoDefinition() {
        // [^x] appears in body but no [^x]: definition exists.
        // The inline reference must survive as .footnoteReference("x").
        // No .footnotes block should be appended (definitions list is empty).
        let blocks = MarkdownParser.parse("See the note.[^x]")
        guard case let .paragraph(inlines) = blocks.first else {
            Issue.record("expected paragraph, got \(blocks)")
            return
        }
        let refInlines = inlines.filter {
            if case .footnoteReference = $0 { return true }
            return false
        }
        #expect(refInlines.count == 1, "expected exactly one footnoteReference inline in \(inlines)")
        if case let .footnoteReference(label) = refInlines[0] {
            #expect(label == "x")
        }
        // No .footnotes block — definitions are empty so the gate is not passed.
        let hasFootnotesBlock = blocks.contains {
            if case .footnotes = $0 { return true }
            return false
        }
        #expect(!hasFootnotesBlock, "expected no .footnotes block when definition is absent")
    }

    // MARK: Case 3 — Dead footnote definition (definition, no in-body reference)

    @Test
    func deadFootnoteDefinitionIncludedInBlock() {
        // [^x]: definition exists but no [^x] reference appears in body.
        // Current behavior: FootnoteExtractor strips the line; MarkdownParser
        // appends .footnotes as long as definitions is non-empty.
        let blocks = MarkdownParser.parse("Body text.\n\n[^x]: an unused note.")
        let footnotesBlocks = blocks.compactMap { block -> [MarkdownFootnote]? in
            if case let .footnotes(notes) = block { return notes }
            return nil
        }
        #expect(footnotesBlocks.count == 1, "expected exactly one .footnotes block in \(blocks)")
        let notes = footnotesBlocks[0]
        #expect(notes.count == 1)
        #expect(notes[0].label == "x")
        // Content should parse to the text of the definition.
        #expect(!(notes[0].content.isEmpty), "footnote content must not be empty")
        let contentText = notes[0].content.compactMap { if case let .text(t) = $0 { return t } else { return nil } }.joined()
        #expect(contentText.contains("an unused note"), "expected definition text in content, got \(notes[0].content)")
    }

    // MARK: Case 4 — Long unbroken URL becomes a single autolink

    @Test
    func longUrlBecomesOneAutolink() {
        let longURL = "https://example.com/a/very/long/path/segment/that/keeps/going/and/going/until/it/is/long.html"
        let blocks = MarkdownParser.parse(longURL)
        guard case let .paragraph(inlines) = blocks.first else {
            Issue.record("expected paragraph, got \(blocks)")
            return
        }
        let linkInlines = inlines.filter {
            if case .link = $0 { return true }
            return false
        }
        #expect(linkInlines.count == 1, "expected exactly one link inline for a bare URL, got \(inlines)")
        guard case let .link(_, url) = linkInlines[0] else { return }
        #expect(url == URL(string: longURL))
    }

    // MARK: Case 5 — Unknown emoji with space before known emoji

    /// Note: InlineLexerTests.test_unknownShortcodeDoesNotLeakIntoNextEmoji covers the
    /// adjacent-colon case (":foo:penguin:" sharing a colon). This test covers the
    /// space-separated variant where ":notreal:" must stay literal and ":penguin:" must
    /// still resolve to the penguin emoji.
    @Test
    func unknownEmojiThenSpaceThenKnownEmoji() {
        let result = MarkdownParser.parse(":notreal: :penguin:")
        guard case let .paragraph(inlines) = result.first else {
            Issue.record("expected paragraph, got \(result)")
            return
        }
        // ":notreal:" must not become any emoji inline.
        let hasUnknownEmoji = inlines.contains {
            if case let .emoji(s) = $0 { return s == ":notreal:" }
            return false
        }
        #expect(!hasUnknownEmoji, ":notreal: must not become an .emoji inline")
        // ":notreal:" should appear as literal text (may be merged with adjacent spaces).
        let allText = inlines.compactMap { if case let .text(t) = $0 { return t } else { return nil } }.joined()
        #expect(allText.contains(":notreal:"), "expected ':notreal:' as literal text in \(inlines)")
        // ":penguin:" must resolve to the penguin unicode scalar.
        let penguinInlines = inlines.filter {
            if case let .emoji(s) = $0 { return s == "\u{1F427}" }
            return false
        }
        #expect(penguinInlines.count == 1, "expected exactly one penguin emoji inline in \(inlines)")
    }
}
