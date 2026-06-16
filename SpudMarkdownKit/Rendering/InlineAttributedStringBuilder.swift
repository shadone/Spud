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
    static func build(_ inlines: [MarkdownInline], context: MarkdownContext) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for inline in inlines {
            out.append(render(inline, context: context, baseFont: context.bodyFont))
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
            m.addAttributes(
                [
                    .link: url,
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

    private static func chip(
        symbol: String,
        text: String,
        url: URL,
        context: MarkdownContext,
        baseFont: UIFont
    ) -> NSAttributedString {
        let m = NSMutableAttributedString()
        if let image = UIImage(systemName: symbol)?
            .withTintColor(context.accentColor, renderingMode: .alwaysOriginal)
        {
            let attachment = NSTextAttachment()
            attachment.image = image
            let size = baseFont.pointSize * 0.85
            attachment.bounds = CGRect(x: 0, y: baseFont.descender * 0.3, width: size, height: size)
            m.append(NSAttributedString(attachment: attachment))
            m.append(NSAttributedString(string: "\u{2009}")) // thin space
        }
        m.append(NSAttributedString(string: text, attributes: [.font: baseFont.withTraits(.traitBold)]))
        m.addAttributes(
            [
                .link: url,
                .foregroundColor: context.accentColor,
                .backgroundColor: context.chipBackground,
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
