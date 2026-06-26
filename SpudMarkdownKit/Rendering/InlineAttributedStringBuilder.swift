//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Builds an `NSAttributedString` from inline markdown for a given context.
/// Mentions/communities encode their destination as an internal
/// `spud-markdown://` URL so the host can resolve navigation without this
/// framework knowing the app's URL scheme.
@MainActor
enum InlineAttributedStringBuilder {
    static func build(
        _ inlines: [MarkdownInline],
        context: MarkdownContext,
        baseFont: UIFont? = nil
    ) -> NSAttributedString {
        let base = baseFont ?? context.bodyFont
        let out = NSMutableAttributedString()
        for inline in inlines {
            out.append(render(inline, context: context, baseFont: base))
        }
        return out
    }

    /// Internal destination URLs for mentions/communities (host decodes).
    static func mentionURL(name: String, instance: String) -> URL {
        internalURL(host: "mention", name: name, instance: instance)
    }

    static func communityURL(name: String, instance: String) -> URL {
        internalURL(host: "community", name: name, instance: instance)
    }

    /// Internal destination URL for a Lemmy object (post/comment) the host resolves
    /// by its federation URL (via `resolve_object`).
    static func objectURL(forResolved url: URL) -> URL {
        var components = URLComponents()
        components.scheme = "spud-markdown"
        components.host = "object"
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return components.url ?? URL(string: "spud-markdown://object")!
    }

    /// If `url` is an explicit Lemmy user (`/u/<name>`), community (`/c/<name>`),
    /// post (`/post/<id>`), or comment (`/comment/<id>`) link, returns the
    /// equivalent internal `spud-markdown://` URL so the host resolves it in-app
    /// instead of opening a browser. Lemmy renders an `@user@instance` /
    /// `!community@instance` reference as a plain link to `https://<instance>/u/<name>`
    /// (or `/c/<name>`); the path may itself carry a federated handle
    /// (`/u/<name>@<home-instance>`), in which case the home instance wins. Posts and
    /// comments carry a numeric id. Returns nil for anything that is not a
    /// recognizable Lemmy link, so ordinary links fall through unchanged.
    static func lemmyReferenceURL(for url: URL) -> URL? {
        guard
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let urlHost = url.host, isLemmyHost(urlHost)
        else {
            return nil
        }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard segments.count == 2 else { return nil }
        let kind = String(segments[0])

        switch kind {
        case "u", "c":
            // The handle is "name" (local) or "name@home-instance" (federated).
            let handle = segments[1].split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(handle[0])
            let instance = handle.count == 2 ? String(handle[1]) : urlHost
            guard isLemmyName(name), isLemmyHost(instance) else { return nil }
            return kind == "u"
                ? mentionURL(name: name, instance: instance)
                : communityURL(name: name, instance: instance)

        case "post", "comment":
            let id = String(segments[1])
            guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
            guard let resolved = URL(string: "https://\(urlHost)/\(kind)/\(id)") else { return nil }
            return objectURL(forResolved: resolved)

        default:
            return nil
        }
    }

    /// A Lemmy local username / community name: ASCII word characters only. The
    /// `isASCII` guard must cover `isNumber` too, or non-ASCII digits (e.g.
    /// Arabic-Indic) would slip through.
    private static func isLemmyName(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }

    /// A plausible instance host: dotted domain of host characters.
    private static func isLemmyHost(_ s: String) -> Bool {
        s.contains(".") && s.allSatisfy { $0 == "." || $0 == "-" || $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// Builds a `spud-markdown://<host>?name=…&instance=…` URL, percent-encoding
    /// the query values. The scheme/host are literals, so `components.url` is
    /// non-nil; the fallback keeps this total without a force-unwrap on input.
    private static func internalURL(host: String, name: String, instance: String) -> URL {
        var components = URLComponents()
        components.scheme = "spud-markdown"
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "instance", value: instance),
        ]
        return components.url ?? URL(string: "spud-markdown://\(host)")!
    }

    private static func render(
        _ inline: MarkdownInline,
        context: MarkdownContext,
        baseFont: UIFont
    ) -> NSAttributedString {
        switch inline {
        case let .text(s):
            return NSAttributedString(string: s, attributes: [.font: baseFont, .foregroundColor: context.labelColor])

        case let .strong(children):
            return mapChildren(children, context: context, baseFont: baseFont.withTraits(.traitBold))

        case let .emphasis(children):
            return mapChildren(children, context: context, baseFont: baseFont.withTraits(.traitItalic))

        case let .strikethrough(children):
            let inner = mapChildren(children, context: context, baseFont: baseFont)
            let m = NSMutableAttributedString(attributedString: inner)
            m.addAttributes(
                [
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: context.secondaryColor,
                ],
                range: NSRange(location: 0, length: m.length)
            )
            return m

        case let .highlight(children):
            let inner = mapChildren(children, context: context, baseFont: baseFont)
            let m = NSMutableAttributedString(attributedString: inner)
            m.addAttribute(
                .backgroundColor,
                value: context.highlightColor,
                range: NSRange(location: 0, length: m.length)
            )
            return m

        case let .code(s):
            return NSAttributedString(string: s, attributes: [
                .font: context.inlineCodeFont,
                .foregroundColor: context.inlineCodeForeground,
                .backgroundColor: context.inlineCodeBackground,
            ])

        case let .superscript(children):
            return script(children, context: context, baseFont: baseFont, offset: baseFont.pointSize * 0.35)

        case let .subscript(children):
            return script(children, context: context, baseFont: baseFont, offset: -(baseFont.pointSize * 0.2))

        case let .link(text, url):
            let inner = mapChildren(text, context: context, baseFont: baseFont)
            let m = NSMutableAttributedString(attributedString: inner)
            // A plain link to a Lemmy user/community resolves in-app rather than
            // opening Safari; ordinary links keep their URL.
            let linkURL = lemmyReferenceURL(for: url) ?? url
            m.addAttributes(
                [
                    .link: linkURL,
                    .foregroundColor: context.accentColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ],
                range: NSRange(location: 0, length: m.length)
            )
            return m

        case let .mention(name, instance):
            return chip(
                symbol: "at",
                text: "\(name)@\(instance)",
                url: mentionURL(name: name, instance: instance),
                context: context,
                baseFont: baseFont
            )

        case let .community(name, instance):
            return chip(
                symbol: "person.2",
                text: "\(name)@\(instance)",
                url: communityURL(name: name, instance: instance),
                context: context,
                baseFont: baseFont
            )

        case let .emoji(s):
            return NSAttributedString(string: s, attributes: [.font: baseFont])

        case let .customEmoji(shortcode):
            return NSAttributedString(
                string: ":\(shortcode):",
                attributes: [.font: baseFont, .foregroundColor: context.secondaryColor]
            )

        case let .footnoteReference(label):
            let small = baseFont.withSize(baseFont.pointSize * 0.78)
            return NSAttributedString(string: "[\(label)]", attributes: [
                .font: small,
                .foregroundColor: context.accentColor,
                .baselineOffset: small.pointSize * 0.3,
                .link: MarkdownFootnoteLink.url(.toDefinition(label: label)),
            ])
        }
    }

    private static func mapChildren(
        _ children: [MarkdownInline],
        context: MarkdownContext,
        baseFont: UIFont
    ) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for child in children {
            out.append(render(child, context: context, baseFont: baseFont))
        }
        return out
    }

    private static func script(
        _ children: [MarkdownInline],
        context: MarkdownContext,
        baseFont: UIFont,
        offset: CGFloat
    ) -> NSAttributedString {
        let small = baseFont.withSize(baseFont.pointSize * 0.72)
        let inner = mapChildren(children, context: context, baseFont: small)
        let m = NSMutableAttributedString(attributedString: inner)
        m.addAttribute(.baselineOffset, value: offset, range: NSRange(location: 0, length: m.length))
        return m
    }

    /// A mention/community handle: a leading glyph + bold accent handle, kept as
    /// real text and marked with `.mentionChipFill` so `ChipBackgroundLayoutManager`
    /// paints a rounded pill behind it. Hair spaces pad the pill off the glyph and
    /// the neighboring words. The whole run carries the internal `.link`.
    private static func chip(
        symbol: String,
        text: String,
        url: URL,
        context: MarkdownContext,
        baseFont: UIFont
    ) -> NSAttributedString {
        let font = baseFont.withTraits(.traitBold)
        let m = NSMutableAttributedString()
        if let image = UIImage(systemName: symbol)?
            .withTintColor(context.accentColor, renderingMode: .alwaysOriginal)
        {
            let attachment = NSTextAttachment()
            attachment.image = image
            let size = font.pointSize * 0.85
            attachment.bounds = CGRect(x: 0, y: font.descender * 0.3, width: size, height: size)
            m.append(NSAttributedString(attachment: attachment))
            m.append(NSAttributedString(string: "\u{202F}")) // narrow no-break space: keep glyph with handle
        }
        m.append(NSAttributedString(string: text, attributes: [.font: font]))
        m.addAttributes(
            [
                .font: font,
                .foregroundColor: context.accentColor,
                .link: url,
                .mentionChipFill: context.chipBackground,
            ],
            range: NSRange(location: 0, length: m.length)
        )
        return m
    }
}

extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var combined = fontDescriptor.symbolicTraits
        combined.insert(traits)
        guard let descriptor = fontDescriptor.withSymbolicTraits(combined) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
