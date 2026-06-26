//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import XCTest
@testable import SpudMarkdownKit

@MainActor
final class InlineAttributedStringBuilderTests: XCTestCase {
    private func build(_ inlines: [MarkdownInline]) -> NSAttributedString {
        InlineAttributedStringBuilder.build(inlines, context: MarkdownContext(kind: .post))
    }

    func test_plainText() {
        XCTAssertEqual(build([.text("hello")]).string, "hello")
    }

    func test_strongIsBold() {
        let s = build([.strong([.text("x")])])
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
    }

    func test_emphasisIsItalic() {
        let s = build([.emphasis([.text("x")])])
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false)
    }

    func test_linkCarriesURL() throws {
        // A plain external link keeps its URL (not a Lemmy user/community/post link).
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))
        let s = build([.link(text: [.text("here")], url: url)])
        XCTAssertEqual(s.attribute(.link, at: 0, effectiveRange: nil) as? URL, url)
    }

    func test_explicitUserLinkResolvesToInternalMention() throws {
        // Lemmy renders @autotldr@lemmings.world as a plain link to /u/autotldr;
        // it must route in-app, not to Safari.
        let url = try XCTUnwrap(URL(string: "https://lemmings.world/u/autotldr"))
        let s = build([.link(text: [.text("@autotldr@lemmings.world")], url: url)])
        let link = try XCTUnwrap(s.attribute(.link, at: 0, effectiveRange: nil) as? URL)
        XCTAssertEqual(link.scheme, "spud-markdown")
        XCTAssertEqual(link.host, "mention")
        let components = try XCTUnwrap(URLComponents(url: link, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "name" }?.value, "autotldr")
        XCTAssertEqual(components.queryItems?.first { $0.name == "instance" }?.value, "lemmings.world")
    }

    func test_explicitCommunityLinkResolvesToInternalCommunity() throws {
        let url = try XCTUnwrap(URL(string: "https://lemmy.world/c/news"))
        let s = build([.link(text: [.text("news")], url: url)])
        let link = try XCTUnwrap(s.attribute(.link, at: 0, effectiveRange: nil) as? URL)
        XCTAssertEqual(link.scheme, "spud-markdown")
        XCTAssertEqual(link.host, "community")
    }

    func test_federatedUserLinkUsesHomeInstanceFromPath() throws {
        // /u/<name>@<home> — the home instance in the path wins over the URL host.
        let url = try XCTUnwrap(URL(string: "https://lemmy.world/u/bob@beehaw.org"))
        let internalURL = try XCTUnwrap(InlineAttributedStringBuilder.lemmyReferenceURL(for: url))
        let components = try XCTUnwrap(URLComponents(url: internalURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "mention")
        XCTAssertEqual(components.queryItems?.first { $0.name == "name" }?.value, "bob")
        XCTAssertEqual(components.queryItems?.first { $0.name == "instance" }?.value, "beehaw.org")
    }

    func test_explicitPostLinkResolvesToObject() throws {
        let url = try XCTUnwrap(URL(string: "https://lemmy.world/post/12345"))
        let s = build([.link(text: [.text("a post")], url: url)])
        let link = try XCTUnwrap(s.attribute(.link, at: 0, effectiveRange: nil) as? URL)
        XCTAssertEqual(link.scheme, "spud-markdown")
        XCTAssertEqual(link.host, "object")
        let components = try XCTUnwrap(URLComponents(url: link, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "url" }?.value, "https://lemmy.world/post/12345")
    }

    func test_explicitCommentLinkResolvesToObject() throws {
        let url = try XCTUnwrap(URL(string: "https://lemmy.world/comment/678"))
        let internalURL = try XCTUnwrap(InlineAttributedStringBuilder.lemmyReferenceURL(for: url))
        XCTAssertEqual(internalURL.host, "object")
        let components = try XCTUnwrap(URLComponents(url: internalURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "url" }?.value, "https://lemmy.world/comment/678")
    }

    func test_nonNumericPostIdIsNotRewritten() throws {
        // /post/<non-numeric> is not a Lemmy post URL.
        let url = try XCTUnwrap(URL(string: "https://example.com/post/hello-world"))
        XCTAssertNil(InlineAttributedStringBuilder.lemmyReferenceURL(for: url))
    }

    func test_nonAsciiUsernameIsNotRewritten() throws {
        // Lemmy usernames are ASCII-only; a /u/ path of non-ASCII digits is not a
        // valid handle and must not be rewritten to an internal mention.
        let url = try XCTUnwrap(URL(string: "https://lemmy.world/u/\u{0661}\u{0662}\u{0663}"))
        XCTAssertNil(InlineAttributedStringBuilder.lemmyReferenceURL(for: url))
    }

    func test_ordinaryLinkIsUnchanged() throws {
        // Non-Lemmy-reference links keep their URL.
        for raw in [
            "https://example.com/u/foo/bar",
            "https://example.com/article",
            "https://lemmy.world/u/foo/bar",
        ] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertNil(InlineAttributedStringBuilder.lemmyReferenceURL(for: url), "\(raw)")
            let s = build([.link(text: [.text("x")], url: url)])
            XCTAssertEqual(s.attribute(.link, at: 0, effectiveRange: nil) as? URL, url, "\(raw)")
        }
    }

    func test_highlightHasBackground() {
        let s = build([.highlight([.text("x")])])
        XCTAssertNotNil(s.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    }

    func test_inlineCodeUsesMonospace() {
        let s = build([.code("ls")])
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) ?? false)
    }

    private func chipFillAndLink(_ s: NSAttributedString) -> (fill: UIColor, url: URL)? {
        let full = NSRange(location: 0, length: s.length)
        var fill: UIColor?
        var url: URL?
        s.enumerateAttribute(.mentionChipFill, in: full) { value, _, _ in
            if let color = value as? UIColor { fill = color }
        }
        s.enumerateAttribute(.link, in: full) { value, _, _ in
            if let value = value as? URL { url = value }
        }
        guard let fill, let url else { return nil }
        return (fill, url)
    }

    func test_mentionRendersHandleTextWithChipFillAndLink() throws {
        let s = build([.mention(name: "alice", instance: "lemmy.world")])
        XCTAssertTrue(s.string.contains("alice@lemmy.world"))
        let chip = try XCTUnwrap(chipFillAndLink(s))
        XCTAssertEqual(chip.url.scheme, "spud-markdown")
        XCTAssertEqual(chip.url.host, "mention")
    }

    func test_communityRendersHandleTextWithChipFillAndLink() throws {
        let s = build([.community(name: "linux", instance: "lemmy.world")])
        XCTAssertTrue(s.string.contains("linux@lemmy.world"))
        let chip = try XCTUnwrap(chipFillAndLink(s))
        XCTAssertEqual(chip.url.host, "community")
    }

    func test_superscriptRaised() {
        let s = build([.text("x"), .superscript([.text("2")])])
        let offset = s.attribute(.baselineOffset, at: s.length - 1, effectiveRange: nil) as? CGFloat
        XCTAssertNotNil(offset)
        XCTAssertGreaterThan(offset ?? 0, 0)
    }

    func test_footnoteReferenceCarriesDefinitionLink() {
        let s = build([.footnoteReference("1")])
        let url = s.attribute(.link, at: 0, effectiveRange: nil) as? URL
        XCTAssertEqual(url.flatMap(MarkdownFootnoteLink.init), .toDefinition(label: "1"))
    }

    func test_mentionWithUnsafeCharactersDoesNotCrash() throws {
        // A name with a space would crash a force-unwrapped URL(string:) — it must
        // not, and the chip must still carry a valid spud-markdown URL.
        let s = build([.mention(name: "alice smith", instance: "lemmy.world")])
        let chip = try XCTUnwrap(chipFillAndLink(s))
        XCTAssertEqual(chip.url.scheme, "spud-markdown")
        XCTAssertEqual(chip.url.host, "mention")
    }
}
