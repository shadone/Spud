//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudMarkdownKit
import SpudUtilKit
import Testing
@testable import Spud

struct CommentLinkPreviewTests {
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

    @Test
    func externalHTTPSLink_displayAndTapAreTheURL() throws {
        let url = try #require(URL(string: "https://example.com/article/42"))
        let blocks = paragraph(.text("see "), .link(text: [.text("this")], url: url), .text(" now"))

        #expect(
            blocks.commentLinkPreviews(limit: 3) ==
                [CommentLinkPreview(displayURL: url, tapURL: url, anchorText: "this", kind: .generic)]
        )
    }

    @Test
    func multipleLinks_inDocumentOrder() throws {
        let a = try #require(URL(string: "https://a.example/1"))
        let b = try #require(URL(string: "https://b.example/2"))
        let blocks = paragraph(autolink(a.absoluteString), .text(" "), autolink(b.absoluteString))

        #expect(blocks.commentLinkPreviews(limit: 3).map(\.tapURL) == [a, b])
    }

    @Test
    func duplicateURL_isDeduplicated() throws {
        let a = try #require(URL(string: "https://a.example/1"))
        let blocks = paragraph(.link(text: [.text("first")], url: a), .text(" "), .link(text: [.text("again")], url: a))

        #expect(blocks.commentLinkPreviews(limit: 3) == [CommentLinkPreview(displayURL: a, tapURL: a, anchorText: "first", kind: .generic)])
    }

    @Test
    func capLimitsCount_keepingFirst() throws {
        let urls = try (0..<5).map { try #require(URL(string: "https://x.example/\($0)")) }
        let inlines = urls.flatMap { [autolink($0.absoluteString), MarkdownInline.text(" ")] }
        let blocks: [MarkdownBlock] = [.paragraph(inlines)]

        #expect(blocks.commentLinkPreviews(limit: 3).map(\.tapURL) == Array(urls.prefix(3)))
    }

    @Test
    func community_synthesizesCSlashName_tapsInternalURL() throws {
        let blocks = paragraph(.community(name: "news", instance: "lemmy.world"))

        let expectedTap = URL.SpudInternalLink.community(name: "news", instance: lemmyWorld).url
        let expectedDisplay = try #require(URL(string: "https://lemmy.world/c/news"))
        #expect(
            blocks.commentLinkPreviews(limit: 3) ==
                [CommentLinkPreview(displayURL: expectedDisplay, tapURL: expectedTap, anchorText: nil, kind: .generic)]
        )
    }

    @Test
    func mention_isSkipped() {
        let blocks = paragraph(.mention(name: "alice", instance: "lemmy.world"))
        #expect(blocks.commentLinkPreviews(limit: 3) == [])
    }

    @Test
    func nonWebLink_isSkipped() throws {
        let mailto = try #require(URL(string: "mailto:a@example.com"))
        let blocks = paragraph(.link(text: [.text("mail")], url: mailto))
        #expect(blocks.commentLinkPreviews(limit: 3) == [])
    }

    @Test
    func linkNestedInEmphasis_isFound() throws {
        let url = try #require(URL(string: "https://example.com/x"))
        let blocks = paragraph(.emphasis([.link(text: [.text("x")], url: url)]))
        #expect(blocks.commentLinkPreviews(limit: 3) == [CommentLinkPreview(displayURL: url, tapURL: url, anchorText: "x", kind: .generic)])
    }

    @Test
    func linksInQuoteAndList_areFound_inOrder() throws {
        let a = try #require(URL(string: "https://a.example/1"))
        let b = try #require(URL(string: "https://b.example/2"))
        let blocks: [MarkdownBlock] = [
            .blockQuote([.paragraph([.link(text: [.text("a")], url: a)])]),
            .unorderedList([MarkdownListItem(blocks: [.paragraph([.link(text: [.text("b")], url: b)])])]),
        ]
        #expect(blocks.commentLinkPreviews(limit: 3).map(\.tapURL) == [a, b])
    }

    @Test
    func noLinks_returnsEmpty() {
        #expect(paragraph(.text("just text")).commentLinkPreviews(limit: 3) == [])
    }

    @Test
    func emptyBlocks_returnsEmpty() {
        #expect([MarkdownBlock]().commentLinkPreviews(limit: 3) == [])
    }

    @Test
    func webLink_carriesAnchorTextAndKind() throws {
        let blocks: [MarkdownBlock] = try [.paragraph([
            .link(text: [.text("Foobar")], url: #require(URL(string: "https://example.com"))),
        ])]
        let previews = blocks.commentLinkPreviews(limit: 3)
        #expect(previews.count == 1)
        #expect(previews[0].anchorText == "Foobar")
        #expect(previews[0].kind == .generic)
    }

    @Test
    func youtubeLink_isVideoKind() throws {
        let blocks: [MarkdownBlock] = try [.paragraph([
            .link(text: [.text("a video")], url: #require(URL(string: "https://youtu.be/dQw4w9WgXcQ"))),
        ])]
        let previews = blocks.commentLinkPreviews(limit: 3)
        #expect(previews.first?.kind == .video)
        #expect(previews.first?.anchorText == "a video")
    }

    @Test
    func frontendPostLink_tapsInAppFederatedResolve() throws {
        // A frontend post URL (`/c/<community>/p/<id>[/<slug>]`, e.g. PieFed /
        // feddit) must open in-app via a federated resolve, not the browser —
        // even on an instance outside the Explorer directory. The card taps the
        // raw URL straight through the known-instance-gated `LemmyURLParser.classify`,
        // so without resolving `tapURL` here it would bounce to Safari, unlike the
        // inline-text render rewrite and the search paste path. `displayURL` stays
        // the human-readable link.
        let raw = try #require(URL(string: "https://piefed.world/c/tech/p/1235129/nsa-is-sabotaging"))
        let canonical = try #require(URL(string: "https://piefed.world/post/1235129"))
        let expectedTap = URL.SpudInternalLink.objectAtURL(url: canonical).url

        let previews = paragraph(autolink(raw.absoluteString)).commentLinkPreviews(limit: 3)
        #expect(previews.count == 1)
        #expect(previews.first?.tapURL == expectedTap)
        #expect(previews.first?.displayURL == raw)
    }
}
