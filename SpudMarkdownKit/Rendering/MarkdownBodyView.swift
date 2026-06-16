//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Renders a parsed markdown body (`[MarkdownBlock]`) as a self-sizing vertical
/// stack of block views, in a given context. Phase 2 renders prose blocks
/// (paragraph, heading, list, quote, thematic break); other block kinds show a
/// labeled placeholder.
@MainActor
public final class MarkdownBodyView: UIView {
    public weak var delegate: MarkdownBodyDelegate?
    private let stack = UIStackView()
    private var context: MarkdownContext

    public init(context: MarkdownContext) {
        self.context = context
        super.init(frame: .zero)
        stack.axis = .vertical
        stack.spacing = context.interBlockGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Replaces the rendered content with `blocks`.
    public func setBlocks(_ blocks: [MarkdownBlock]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for view in blocks.map({ view(for: $0) }) {
            stack.addArrangedSubview(view)
        }
    }

    // MARK: Block -> view

    private func view(for block: MarkdownBlock) -> UIView {
        switch block {
        case let .paragraph(inlines):
            return prose(InlineAttributedStringBuilder.build(inlines, context: context))
        case let .heading(level, inlines):
            return prose(heading(level: level, inlines: inlines))
        case let .unorderedList(items):
            return prose(listAttributed(items, ordered: false, start: 1))
        case let .orderedList(start, items):
            return prose(listAttributed(items, ordered: true, start: start))
        case let .blockQuote(children):
            let quote = QuoteBlockView(context: context)
            for child in children {
                quote.addArrangedChild(view(for: child))
            }
            return quote
        case .thematicBreak:
            return ThematicBreakView()
        case .codeBlock: return PlaceholderBlockView(label: "code")
        case .table: return PlaceholderBlockView(label: "table")
        case .spoiler: return PlaceholderBlockView(label: "spoiler")
        case .image: return PlaceholderBlockView(label: "image")
        case .audio: return PlaceholderBlockView(label: "audio")
        case .video: return PlaceholderBlockView(label: "video")
        case .footnotes: return PlaceholderBlockView(label: "footnotes")
        }
    }

    private func prose(_ attributed: NSAttributedString) -> ProseBlockView {
        let view = ProseBlockView()
        let m = NSMutableAttributedString(attributedString: attributed)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = context.lineHeightMultiple
        m.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: m.length))
        view.attributedText = m
        view.onTapLink = { [weak self] url in self?.delegate?.markdownBody(didTapLink: url) }
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

    private func listAttributed(_ items: [MarkdownListItem], ordered: Bool, start: Int) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (i, item) in items.enumerated() {
            let marker = ordered ? "\(start + i)." : "\u{2022}"
            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = context.listIndent
            paragraph.firstLineHeadIndent = 0
            paragraph.lineHeightMultiple = context.lineHeightMultiple
            let markerStr = NSAttributedString(string: "\(marker)\t", attributes: [
                .font: context.bodyFont, .foregroundColor: context.secondaryColor,
                .paragraphStyle: paragraph,
            ])
            out.append(markerStr)
            if case let .paragraph(inlines)? = item.blocks.first {
                let content = NSMutableAttributedString(
                    attributedString: InlineAttributedStringBuilder.build(inlines, context: context)
                )
                content.addAttribute(
                    .paragraphStyle,
                    value: paragraph,
                    range: NSRange(location: 0, length: content.length)
                )
                out.append(content)
            }
            if i < items.count - 1 { out.append(NSAttributedString(string: "\n")) }
        }
        return out
    }
}
