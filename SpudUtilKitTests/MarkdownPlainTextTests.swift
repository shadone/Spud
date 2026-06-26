//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct MarkdownPlainTextTests {
    // MARK: Headings

    @Test
    func atxHeading_stripsLeadingHashes() {
        #expect(
            MarkdownPlainText.preview(from: "##### This is an automated archive") ==
                "This is an automated archive"
        )
    }

    @Test
    func atxHeading_stripsTrailingHashes() {
        #expect(MarkdownPlainText.preview(from: "# Title #") == "Title")
    }

    @Test
    func multiBlock_collapsesToOneLine() {
        #expect(
            MarkdownPlainText.preview(from: "# Heading\n\nSome intro text.") ==
                "Heading Some intro text."
        )
    }

    // MARK: Emphasis

    @Test
    func emphasisMarkers_removed() {
        #expect(
            MarkdownPlainText.preview(from: "This is **bold** and *italic* and ~~gone~~.") ==
                "This is bold and italic and gone."
        )
    }

    @Test
    func boldItalicCombo_removed() {
        #expect(MarkdownPlainText.preview(from: "***wow***") == "wow")
    }

    @Test
    func inlineCode_backticksRemoved() {
        #expect(MarkdownPlainText.preview(from: "`let x = 1`") == "let x = 1")
    }

    @Test
    func intrawordDoubleUnderscore_survives() {
        #expect(
            MarkdownPlainText.preview(from: "call foo__bar__baz now") ==
                "call foo__bar__baz now"
        )
    }

    @Test
    func standaloneDoubleUnderscoreBold_stripped() {
        #expect(
            MarkdownPlainText.preview(from: "this __word__ here") ==
                "this word here"
        )
    }

    @Test
    func escapedAsterisks_survivesAsLiteral() {
        #expect(
            MarkdownPlainText.preview(from: "\\*not italic\\*") ==
                "*not italic*"
        )
    }

    // MARK: Links / images

    @Test
    func inlineLink_keepsTextDropsUrl() {
        #expect(
            MarkdownPlainText.preview(from: "see [the docs](https://example.com) now") ==
                "see the docs now"
        )
    }

    @Test
    func image_keepsAltDropsUrl() {
        #expect(
            MarkdownPlainText.preview(from: "![a cat](https://example.com/cat.png)") ==
                "a cat"
        )
    }

    @Test
    func referenceStyleLink_keepsText() {
        #expect(
            MarkdownPlainText.preview(from: "see [the docs][1] please") ==
                "see the docs please"
        )
    }

    @Test
    func autolink_keepsBareUrl() {
        #expect(
            MarkdownPlainText.preview(from: "<https://example.com>") ==
                "https://example.com"
        )
    }

    // MARK: Block markers

    @Test
    func blockquoteMarker_removed() {
        #expect(MarkdownPlainText.preview(from: "> quoted line") == "quoted line")
    }

    @Test
    func multiLevelBlockquote_markersRemoved() {
        #expect(MarkdownPlainText.preview(from: "> > deep quote") == "deep quote")
    }

    @Test
    func fencedCode_withInfoString_dropsDelimiterAndTag() {
        #expect(
            MarkdownPlainText.preview(from: "```swift\nlet x = 1\n```") ==
                "let x = 1"
        )
    }

    @Test
    func tildeFence_dropsDelimiter() {
        #expect(MarkdownPlainText.preview(from: "~~~\ncode\n~~~") == "code")
    }

    @Test
    func spoilerBlock_titleAndContentKept() {
        #expect(
            MarkdownPlainText.preview(from: "::: spoiler Big reveal\nhidden text\n:::") ==
                "Big reveal hidden text"
        )
    }

    @Test
    func unorderedList_markersRemovedAndItemsJoined() {
        #expect(MarkdownPlainText.preview(from: "- one\n- two") == "one two")
    }

    @Test
    func orderedList_markersRemoved() {
        #expect(MarkdownPlainText.preview(from: "1. first\n2. second") == "first second")
    }

    @Test
    func thematicBreak_lineDropped() {
        #expect(
            MarkdownPlainText.preview(from: "before\n\n---\n\nafter") ==
                "before after"
        )
    }

    // MARK: Whitespace / empties

    @Test
    func whitespace_collapsedAndTrimmed() {
        #expect(
            MarkdownPlainText.preview(from: "   lots   of    space   ") ==
                "lots of space"
        )
    }

    @Test
    func emptyInput_returnsEmpty() {
        #expect(MarkdownPlainText.preview(from: "") == "")
    }

    @Test
    func whitespaceOnlyInput_returnsEmpty() {
        #expect(MarkdownPlainText.preview(from: "   \n\t  \n ") == "")
    }

    // MARK: Plain text untouched

    @Test
    func plainParagraph_returnedUnchanged() {
        #expect(MarkdownPlainText.preview(from: "Just plain text.") == "Just plain text.")
    }

    @Test
    func snakeCase_notMangled() {
        #expect(
            MarkdownPlainText.preview(from: "call some_function_name here") ==
                "call some_function_name here"
        )
    }

    @Test
    func bareUrl_leftIntact() {
        #expect(
            MarkdownPlainText.preview(from: "visit https://example.com today") ==
                "visit https://example.com today"
        )
    }
}
