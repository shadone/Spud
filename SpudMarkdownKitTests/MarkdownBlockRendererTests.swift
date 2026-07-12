//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
import UIKit
@testable import SpudMarkdownKit

@MainActor
struct MarkdownBlockRendererTests {
    private func renderer() -> MarkdownBlockRenderer {
        MarkdownBlockRenderer(context: MarkdownContext(kind: .post))
    }

    @Test
    func paragraphRendersProseBlockView() {
        let view = renderer().view(for: .paragraph([.text("hi")]))
        #expect(view is ProseBlockView)
    }

    @Test
    func thematicBreakRendersThematicBreakView() {
        #expect(renderer().view(for: .thematicBreak) is ThematicBreakView)
    }

    @Test
    func blockQuoteRendersQuoteBlockView() {
        let view = renderer().view(for: .blockQuote([.paragraph([.text("q")])]))
        #expect(view is QuoteBlockView)
    }

    @Test
    func viewsForBlocksReturnsOnePerBlock() {
        let views = renderer().views(for: [.paragraph([.text("a")]), .thematicBreak])
        #expect(views.count == 2)
    }

    @Test
    func imageRendersImageBlockView() throws {
        let image = try MarkdownImage(url: #require(URL(string: "https://example.com/a.jpg")), altText: "alt")
        #expect(renderer().view(for: .image(image)) is ImageBlockView)
    }

    @Test
    func audioRendersAudioBlockView() throws {
        #expect(try renderer().view(for: .audio(url: #require(URL(string: "https://example.com/a.mp3")))) is AudioBlockView)
    }

    @Test
    func videoRendersVideoBlockView() throws {
        #expect(try renderer().view(for: .video(url: #require(URL(string: "https://example.com/a.mp4")))) is VideoBlockView)
    }

    private func headingText(_ block: MarkdownBlock) throws -> NSAttributedString {
        let view = renderer().view(for: block)
        let prose = try #require(view as? ProseBlockView)
        return try #require(prose.attributedText)
    }

    @Test
    func h6UppercasesAndKeepsLinkTappable() throws {
        let url = try #require(URL(string: "https://example.com"))
        let s = try headingText(.heading(level: 6, [.text("see "), .link(text: [.text("docs")], url: url)]))
        #expect(s.string == "SEE DOCS")
        let linkRange = (s.string as NSString).range(of: "DOCS")
        #expect(s.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL == url)
    }

    @Test
    func h6PreservesItalicRun() throws {
        let s = try headingText(.heading(level: 6, [.text("a "), .emphasis([.text("b")])]))
        #expect(s.string == "A B")
        let italicRange = (s.string as NSString).range(of: "B")
        let font = s.attribute(.font, at: italicRange.location, effectiveRange: nil) as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false, "italic run lost in H6")
    }

    // MARK: - onLinkMenu forwarding (long-press link menu)

    @Test
    func onLinkMenuForwardsThroughProseView() throws {
        let renderer = renderer()
        var received: URL?
        renderer.onLinkMenu = { url in
            received = url
            return UITextItem.MenuConfiguration(menu: UIMenu())
        }
        let url = try #require(URL(string: "spud-markdown://mention?name=hiking&instance=fediverse.social"))
        let prose = try #require(renderer.view(for: .paragraph([.link(text: [.text("@hiking")], url: url)])) as? ProseBlockView)

        let config = prose.onLinkMenu?(url)

        #expect(received == url)
        #expect(config != nil)
    }

    @Test
    func onLinkMenuNilWhenRendererHasNoHook() throws {
        // With no renderer hook, the prose view's hook resolves to nil, so the
        // delegate method returns nil and the long-press menu is suppressed
        // (never UIKit's crashing default preview).
        let renderer = renderer()
        let url = try #require(URL(string: "https://example.com"))
        let prose = try #require(renderer.view(for: .paragraph([.link(text: [.text("x")], url: url)])) as? ProseBlockView)

        #expect(prose.onLinkMenu?(url) == nil)
    }
}
