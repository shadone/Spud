//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

final class MarkdownPlainTextTests: XCTestCase {
    // MARK: Headings

    func test_atxHeading_stripsLeadingHashes() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "##### This is an automated archive"),
            "This is an automated archive"
        )
    }

    func test_atxHeading_stripsTrailingHashes() {
        XCTAssertEqual(MarkdownPlainText.preview(from: "# Title #"), "Title")
    }

    func test_multiBlock_collapsesToOneLine() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "# Heading\n\nSome intro text."),
            "Heading Some intro text."
        )
    }

    // MARK: Emphasis

    func test_emphasisMarkers_removed() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "This is **bold** and *italic* and ~~gone~~."),
            "This is bold and italic and gone."
        )
    }

    func test_boldItalicCombo_removed() {
        XCTAssertEqual(MarkdownPlainText.preview(from: "***wow***"), "wow")
    }

    func test_inlineCode_backticksRemoved() {
        XCTAssertEqual(MarkdownPlainText.preview(from: "`let x = 1`"), "let x = 1")
    }

    func test_intrawordDoubleUnderscore_survives() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "call foo__bar__baz now"),
            "call foo__bar__baz now"
        )
    }

    func test_standaloneDoubleUnderscoreBold_stripped() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "this __word__ here"),
            "this word here"
        )
    }

    func test_escapedAsterisks_survivesAsLiteral() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "\\*not italic\\*"),
            "*not italic*"
        )
    }

    // MARK: Links / images

    func test_inlineLink_keepsTextDropsUrl() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "see [the docs](https://example.com) now"),
            "see the docs now"
        )
    }

    func test_image_keepsAltDropsUrl() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "![a cat](https://example.com/cat.png)"),
            "a cat"
        )
    }

    func test_referenceStyleLink_keepsText() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "see [the docs][1] please"),
            "see the docs please"
        )
    }

    func test_autolink_keepsBareUrl() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "<https://example.com>"),
            "https://example.com"
        )
    }

    // MARK: Block markers

    func test_blockquoteMarker_removed() {
        XCTAssertEqual(MarkdownPlainText.preview(from: "> quoted line"), "quoted line")
    }

    func test_multiLevelBlockquote_markersRemoved() {
        XCTAssertEqual(MarkdownPlainText.preview(from: "> > deep quote"), "deep quote")
    }

    func test_fencedCode_withInfoString_dropsDelimiterAndTag() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "```swift\nlet x = 1\n```"),
            "let x = 1"
        )
    }

    func test_tildeFence_dropsDelimiter() {
        XCTAssertEqual(MarkdownPlainText.preview(from: "~~~\ncode\n~~~"), "code")
    }

    func test_spoilerBlock_titleAndContentKept() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "::: spoiler Big reveal\nhidden text\n:::"),
            "Big reveal hidden text"
        )
    }

    func test_unorderedList_markersRemovedAndItemsJoined() {
        XCTAssertEqual(MarkdownPlainText.preview(from: "- one\n- two"), "one two")
    }

    func test_orderedList_markersRemoved() {
        XCTAssertEqual(MarkdownPlainText.preview(from: "1. first\n2. second"), "first second")
    }

    func test_thematicBreak_lineDropped() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "before\n\n---\n\nafter"),
            "before after"
        )
    }

    // MARK: Whitespace / empties

    func test_whitespace_collapsedAndTrimmed() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "   lots   of    space   "),
            "lots of space"
        )
    }

    func test_emptyInput_returnsEmpty() {
        XCTAssertEqual(MarkdownPlainText.preview(from: ""), "")
    }

    func test_whitespaceOnlyInput_returnsEmpty() {
        XCTAssertEqual(MarkdownPlainText.preview(from: "   \n\t  \n "), "")
    }

    // MARK: Plain text untouched

    func test_plainParagraph_returnedUnchanged() {
        XCTAssertEqual(MarkdownPlainText.preview(from: "Just plain text."), "Just plain text.")
    }

    func test_snakeCase_notMangled() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "call some_function_name here"),
            "call some_function_name here"
        )
    }

    func test_bareUrl_leftIntact() {
        XCTAssertEqual(
            MarkdownPlainText.preview(from: "visit https://example.com today"),
            "visit https://example.com today"
        )
    }
}
