//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Builds a `UIView` for each `MarkdownBlock`, in a given context. Shared by
/// `MarkdownBodyView` and by nesting block views (spoilers, lists) so child
/// blocks render through the same path. `onTapLink` forwards body link taps;
/// `onContentSizeChange` lets an interactive child (a spoiler) ask the host to
/// re-measure after it grows/shrinks.
/// `onTapImage` / `onTapVideo` / `onTapAudio` forward media taps to the host;
/// `imageLoader` asynchronously provides decoded images for `.image` blocks.
@MainActor
final class MarkdownBlockRenderer {
    let context: MarkdownContext
    var onTapLink: ((URL) -> Void)?
    var onContentSizeChange: (() -> Void)?
    var onTapImage: ((URL, String?, CGRect) -> Void)?
    var onTapVideo: ((URL) -> Void)?
    var onTapAudio: ((URL) -> Void)?
    var imageLoader: MarkdownImageLoader?

    init(context: MarkdownContext) {
        self.context = context
    }

    func views(for blocks: [MarkdownBlock]) -> [UIView] {
        blocks.map { view(for: $0) }
    }

    func view(for block: MarkdownBlock) -> UIView {
        switch block {
        case let .paragraph(inlines):
            return prose(InlineAttributedStringBuilder.build(inlines, context: context))
        case let .heading(level, inlines):
            return prose(heading(level: level, inlines: inlines))
        case let .unorderedList(items):
            return ListBlockView(items: items, ordered: false, start: 1, depth: 0, context: context, renderer: self)
        case let .orderedList(start, items):
            return ListBlockView(items: items, ordered: true, start: start, depth: 0, context: context, renderer: self)
        case let .blockQuote(children):
            let quote = QuoteBlockView(context: context)
            for child in children {
                quote.addArrangedChild(view(for: child))
            }
            return quote
        case .thematicBreak:
            return ThematicBreakView()
        case let .codeBlock(language, code):
            return CodeBlockView(language: language, code: code, context: context)
        case let .table(table):
            return TableBlockView(table: table, context: context)
        case let .spoiler(title, children):
            return SpoilerBlockView(title: title, children: children, context: context, renderer: self)
        case let .image(image):
            return ImageBlockView(
                image: image,
                context: context,
                onTapImage: onTapImage,
                onOpenInBrowser: onTapLink,
                onContentSizeChange: onContentSizeChange,
                loader: imageLoader
            )
        case let .audio(url):
            return AudioBlockView(url: url, context: context, onTap: onTapAudio)
        case let .video(url):
            return VideoBlockView(url: url, context: context, onTap: onTapVideo)
        case let .footnotes(footnotes):
            return FootnotesBlockView(footnotes: footnotes, context: context, renderer: self)
        }
    }

    func prose(_ attributed: NSAttributedString) -> ProseBlockView {
        let view = ProseBlockView()
        let m = NSMutableAttributedString(attributedString: attributed)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = context.lineHeightMultiple
        m.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: m.length))
        view.attributedText = m
        view.tintColor = context.accentColor
        view.onTapLink = { [weak self] url in self?.onTapLink?(url) }
        return view
    }

    private func heading(level: Int, inlines: [MarkdownInline]) -> NSAttributedString {
        let font = context.headingFont(level: level)
        let color: UIColor = level == 6 ? context.secondaryColor : context.labelColor
        let inner = InlineAttributedStringBuilder.build(inlines, context: context)
        let m = NSMutableAttributedString(attributedString: inner)
        let full = NSRange(location: 0, length: m.length)
        m.addAttributes([.font: font, .foregroundColor: color], range: full)
        if level == 6 {
            m.replaceCharacters(in: full, with: NSAttributedString(
                string: m.string.uppercased(),
                attributes: [.font: font, .foregroundColor: color]
            ))
        }
        return m
    }
}
