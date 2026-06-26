//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
import UIKit
@testable import SpudMarkdownKit

@MainActor
struct InlineAttributedStringBuilderTests {
    private func build(_ inlines: [MarkdownInline]) -> NSAttributedString {
        InlineAttributedStringBuilder.build(inlines, context: MarkdownContext(kind: .post))
    }

    @Test
    func plainText() {
        #expect(build([.text("hello")]).string == "hello")
    }

    @Test
    func strongIsBold() {
        let s = build([.strong([.text("x")])])
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
    }

    @Test
    func emphasisIsItalic() {
        let s = build([.emphasis([.text("x")])])
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false)
    }

    @Test
    func linkCarriesURL() throws {
        // A plain external link keeps its URL (not a Lemmy user/community/post link).
        let url = try #require(URL(string: "https://example.com/article"))
        let s = build([.link(text: [.text("here")], url: url)])
        #expect(s.attribute(.link, at: 0, effectiveRange: nil) as? URL == url)
    }

    @Test
    func explicitUserLinkResolvesToInternalMention() throws {
        // Lemmy renders @autotldr@lemmings.world as a plain link to /u/autotldr;
        // it must route in-app, not to Safari.
        let url = try #require(URL(string: "https://lemmings.world/u/autotldr"))
        let s = build([.link(text: [.text("@autotldr@lemmings.world")], url: url)])
        let link = try #require(s.attribute(.link, at: 0, effectiveRange: nil) as? URL)
        #expect(link.scheme == "spud-markdown")
        #expect(link.host == "mention")
        let components = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first { $0.name == "name" }?.value == "autotldr")
        #expect(components.queryItems?.first { $0.name == "instance" }?.value == "lemmings.world")
    }

    @Test
    func explicitCommunityLinkResolvesToInternalCommunity() throws {
        let url = try #require(URL(string: "https://lemmy.world/c/news"))
        let s = build([.link(text: [.text("news")], url: url)])
        let link = try #require(s.attribute(.link, at: 0, effectiveRange: nil) as? URL)
        #expect(link.scheme == "spud-markdown")
        #expect(link.host == "community")
    }

    @Test
    func federatedUserLinkUsesHomeInstanceFromPath() throws {
        // /u/<name>@<home> — the home instance in the path wins over the URL host.
        let url = try #require(URL(string: "https://lemmy.world/u/bob@beehaw.org"))
        let internalURL = try #require(InlineAttributedStringBuilder.lemmyReferenceURL(for: url))
        let components = try #require(URLComponents(url: internalURL, resolvingAgainstBaseURL: false))
        #expect(components.host == "mention")
        #expect(components.queryItems?.first { $0.name == "name" }?.value == "bob")
        #expect(components.queryItems?.first { $0.name == "instance" }?.value == "beehaw.org")
    }

    @Test
    func explicitPostLinkResolvesToObject() throws {
        let url = try #require(URL(string: "https://lemmy.world/post/12345"))
        let s = build([.link(text: [.text("a post")], url: url)])
        let link = try #require(s.attribute(.link, at: 0, effectiveRange: nil) as? URL)
        #expect(link.scheme == "spud-markdown")
        #expect(link.host == "object")
        let components = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first { $0.name == "url" }?.value == "https://lemmy.world/post/12345")
    }

    @Test
    func frontendPostLink_resolvesToCanonicalObject() throws {
        // The form some instances use: /c/<community>/p/<id>[/<slug>].
        let url = try #require(URL(string: "https://feddit.online/c/opensource/p/1784296/favorite-open-source-game"))
        let internalURL = try #require(InlineAttributedStringBuilder.lemmyReferenceURL(for: url))
        #expect(internalURL.host == "object")
        let components = try #require(URLComponents(url: internalURL, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first { $0.name == "url" }?.value == "https://feddit.online/post/1784296")
    }

    @Test
    func frontendPostLink_withoutSlug() throws {
        let url = try #require(URL(string: "https://feddit.online/c/opensource/p/1784296"))
        let internalURL = try #require(InlineAttributedStringBuilder.lemmyReferenceURL(for: url))
        #expect(internalURL.host == "object")
    }

    @Test
    func frontendPostLink_nonNumericId_isNil() throws {
        let url = try #require(URL(string: "https://feddit.online/c/opensource/p/abc/slug"))
        #expect(InlineAttributedStringBuilder.lemmyReferenceURL(for: url) == nil)
    }

    @Test
    func plainCommunityLink_stillResolvesToCommunity() throws {
        // A 2-segment /c/<name> is a community link, not the frontend post form.
        let url = try #require(URL(string: "https://lemmy.world/c/news"))
        let internalURL = try #require(InlineAttributedStringBuilder.lemmyReferenceURL(for: url))
        #expect(internalURL.host == "community")
    }

    @Test
    func explicitCommentLinkResolvesToObject() throws {
        let url = try #require(URL(string: "https://lemmy.world/comment/678"))
        let internalURL = try #require(InlineAttributedStringBuilder.lemmyReferenceURL(for: url))
        #expect(internalURL.host == "object")
        let components = try #require(URLComponents(url: internalURL, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first { $0.name == "url" }?.value == "https://lemmy.world/comment/678")
    }

    @Test
    func nonNumericPostIdIsNotRewritten() throws {
        // /post/<non-numeric> is not a Lemmy post URL.
        let url = try #require(URL(string: "https://example.com/post/hello-world"))
        #expect(InlineAttributedStringBuilder.lemmyReferenceURL(for: url) == nil)
    }

    @Test
    func nonAsciiUsernameIsNotRewritten() throws {
        // Lemmy usernames are ASCII-only; a /u/ path of non-ASCII digits is not a
        // valid handle and must not be rewritten to an internal mention.
        let url = try #require(URL(string: "https://lemmy.world/u/\u{0661}\u{0662}\u{0663}"))
        #expect(InlineAttributedStringBuilder.lemmyReferenceURL(for: url) == nil)
    }

    @Test
    func ordinaryLinkIsUnchanged() throws {
        // Non-Lemmy-reference links keep their URL.
        for raw in [
            "https://example.com/u/foo/bar",
            "https://example.com/article",
            "https://lemmy.world/u/foo/bar",
        ] {
            let url = try #require(URL(string: raw))
            #expect(InlineAttributedStringBuilder.lemmyReferenceURL(for: url) == nil, "\(raw)")
            let s = build([.link(text: [.text("x")], url: url)])
            #expect(s.attribute(.link, at: 0, effectiveRange: nil) as? URL == url, "\(raw)")
        }
    }

    @Test
    func highlightHasBackground() {
        let s = build([.highlight([.text("x")])])
        #expect(s.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil)
    }

    @Test
    func inlineCodeUsesMonospace() {
        let s = build([.code("ls")])
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) ?? false)
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

    @Test
    func mentionRendersHandleTextWithChipFillAndLink() throws {
        let s = build([.mention(name: "alice", instance: "lemmy.world")])
        #expect(s.string.contains("alice@lemmy.world"))
        let chip = try #require(chipFillAndLink(s))
        #expect(chip.url.scheme == "spud-markdown")
        #expect(chip.url.host == "mention")
    }

    @Test
    func communityRendersHandleTextWithChipFillAndLink() throws {
        let s = build([.community(name: "linux", instance: "lemmy.world")])
        #expect(s.string.contains("linux@lemmy.world"))
        let chip = try #require(chipFillAndLink(s))
        #expect(chip.url.host == "community")
    }

    @Test
    func superscriptRaised() {
        let s = build([.text("x"), .superscript([.text("2")])])
        let offset = s.attribute(.baselineOffset, at: s.length - 1, effectiveRange: nil) as? CGFloat
        #expect(offset != nil)
        #expect((offset ?? 0) > 0)
    }

    @Test
    func footnoteReferenceCarriesDefinitionLink() {
        let s = build([.footnoteReference("1")])
        let url = s.attribute(.link, at: 0, effectiveRange: nil) as? URL
        #expect(url.flatMap(MarkdownFootnoteLink.init) == .toDefinition(label: "1"))
    }

    @Test
    func mentionWithUnsafeCharactersDoesNotCrash() throws {
        // A name with a space would crash a force-unwrapped URL(string:) — it must
        // not, and the chip must still carry a valid spud-markdown URL.
        let s = build([.mention(name: "alice smith", instance: "lemmy.world")])
        let chip = try #require(chipFillAndLink(s))
        #expect(chip.url.scheme == "spud-markdown")
        #expect(chip.url.host == "mention")
    }
}
