//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudMarkdownKit
import SpudUtilKit
import XCTest
@testable import Spud

final class CommentLinkPreviewTests: XCTestCase {
    private let lemmyWorld = InstanceActorId(from: "https://lemmy.world")!

    /// Wraps inlines in a single paragraph block.
    private func paragraph(_ inlines: MarkdownInline...) -> [MarkdownBlock] {
        [.paragraph(inlines)]
    }

    /// A `.link` inline whose display text is the URL string itself (how a bare
    /// autolinked URL is represented).
    private func autolink(_ urlString: String) -> MarkdownInline {
        .link(text: [.text(urlString)], url: URL(string: urlString)!)
    }

    func test_externalHTTPSLink_displayAndTapAreTheURL() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/article/42"))
        let blocks = paragraph(.text("see "), .link(text: [.text("this")], url: url), .text(" now"))

        XCTAssertEqual(
            blocks.commentLinkPreviews(limit: 3),
            [CommentLinkPreview(displayURL: url, tapURL: url, anchorText: "this", kind: .generic)]
        )
    }

    func test_multipleLinks_inDocumentOrder() throws {
        let a = try XCTUnwrap(URL(string: "https://a.example/1"))
        let b = try XCTUnwrap(URL(string: "https://b.example/2"))
        let blocks = paragraph(autolink(a.absoluteString), .text(" "), autolink(b.absoluteString))

        XCTAssertEqual(blocks.commentLinkPreviews(limit: 3).map(\.tapURL), [a, b])
    }

    func test_duplicateURL_isDeduplicated() throws {
        let a = try XCTUnwrap(URL(string: "https://a.example/1"))
        let blocks = paragraph(.link(text: [.text("first")], url: a), .text(" "), .link(text: [.text("again")], url: a))

        XCTAssertEqual(blocks.commentLinkPreviews(limit: 3), [CommentLinkPreview(displayURL: a, tapURL: a, anchorText: "first", kind: .generic)])
    }

    func test_capLimitsCount_keepingFirst() throws {
        let urls = try (0..<5).map { try XCTUnwrap(URL(string: "https://x.example/\($0)")) }
        let inlines = urls.flatMap { [autolink($0.absoluteString), MarkdownInline.text(" ")] }
        let blocks: [MarkdownBlock] = [.paragraph(inlines)]

        XCTAssertEqual(blocks.commentLinkPreviews(limit: 3).map(\.tapURL), Array(urls.prefix(3)))
    }

    func test_community_synthesizesCSlashName_tapsInternalURL() throws {
        let blocks = paragraph(.community(name: "news", instance: "lemmy.world"))

        let expectedTap = URL.SpudInternalLink.community(name: "news", instance: lemmyWorld).url
        let expectedDisplay = try XCTUnwrap(URL(string: "https://lemmy.world/c/news"))
        XCTAssertEqual(
            blocks.commentLinkPreviews(limit: 3),
            [CommentLinkPreview(displayURL: expectedDisplay, tapURL: expectedTap, anchorText: nil, kind: .generic)]
        )
    }

    func test_mention_isSkipped() {
        let blocks = paragraph(.mention(name: "alice", instance: "lemmy.world"))
        XCTAssertEqual(blocks.commentLinkPreviews(limit: 3), [])
    }

    func test_nonWebLink_isSkipped() throws {
        let mailto = try XCTUnwrap(URL(string: "mailto:a@example.com"))
        let blocks = paragraph(.link(text: [.text("mail")], url: mailto))
        XCTAssertEqual(blocks.commentLinkPreviews(limit: 3), [])
    }

    func test_linkNestedInEmphasis_isFound() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/x"))
        let blocks = paragraph(.emphasis([.link(text: [.text("x")], url: url)]))
        XCTAssertEqual(blocks.commentLinkPreviews(limit: 3), [CommentLinkPreview(displayURL: url, tapURL: url, anchorText: "x", kind: .generic)])
    }

    func test_linksInQuoteAndList_areFound_inOrder() throws {
        let a = try XCTUnwrap(URL(string: "https://a.example/1"))
        let b = try XCTUnwrap(URL(string: "https://b.example/2"))
        let blocks: [MarkdownBlock] = [
            .blockQuote([.paragraph([.link(text: [.text("a")], url: a)])]),
            .unorderedList([MarkdownListItem(blocks: [.paragraph([.link(text: [.text("b")], url: b)])])]),
        ]
        XCTAssertEqual(blocks.commentLinkPreviews(limit: 3).map(\.tapURL), [a, b])
    }

    func test_noLinks_returnsEmpty() {
        XCTAssertEqual(paragraph(.text("just text")).commentLinkPreviews(limit: 3), [])
    }

    func test_emptyBlocks_returnsEmpty() {
        XCTAssertEqual([MarkdownBlock]().commentLinkPreviews(limit: 3), [])
    }

    func test_webLink_carriesAnchorTextAndKind() throws {
        let blocks: [MarkdownBlock] = try [.paragraph([
            .link(text: [.text("Foobar")], url: XCTUnwrap(URL(string: "https://example.com"))),
        ])]
        let previews = blocks.commentLinkPreviews(limit: 3)
        XCTAssertEqual(previews.count, 1)
        XCTAssertEqual(previews[0].anchorText, "Foobar")
        XCTAssertEqual(previews[0].kind, .generic)
    }

    func test_youtubeLink_isVideoKind() throws {
        let blocks: [MarkdownBlock] = try [.paragraph([
            .link(text: [.text("a video")], url: XCTUnwrap(URL(string: "https://youtu.be/dQw4w9WgXcQ"))),
        ])]
        let previews = blocks.commentLinkPreviews(limit: 3)
        XCTAssertEqual(previews.first?.kind, .video)
        XCTAssertEqual(previews.first?.anchorText, "a video")
    }
}
