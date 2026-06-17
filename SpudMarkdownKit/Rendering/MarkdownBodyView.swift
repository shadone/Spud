//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Renders a parsed markdown body (`[MarkdownBlock]`) as a self-sizing vertical
/// stack of block views, in a given context, via `MarkdownBlockRenderer`.
@MainActor
public final class MarkdownBodyView: UIView {
    public weak var delegate: MarkdownBodyDelegate?
    private let stack = UIStackView()
    private let renderer: MarkdownBlockRenderer

    /// label -> the view holding that footnote's definition (jump destination of a
    /// `[^n]` reference) and the view holding its reference (jump destination of the
    /// definition's return arrow). Rebuilt on every `setBlocks`.
    private var footnoteDefinitionRows: [String: UIView] = [:]
    private var footnoteReferenceRows: [String: UIView] = [:]

    /// Host-supplied async image provider. Set this BEFORE `setBlocks(_:)` so
    /// the image blocks pick it up as they are built.
    public var imageLoader: MarkdownImageLoader? {
        didSet { renderer.imageLoader = imageLoader }
    }

    public init(context: MarkdownContext) {
        renderer = MarkdownBlockRenderer(context: context)
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
        renderer.onTapLink = { [weak self] url in
            guard let self else { return }
            // Footnote jumps stay inside the body; everything else goes to the host.
            if let footnote = MarkdownFootnoteLink(url) {
                scrollToFootnote(footnote)
            } else {
                delegate?.markdownBody(didTapLink: url)
            }
        }
        renderer.onContentSizeChange = { [weak self] in
            self?.setNeedsLayout()
            self?.invalidateIntrinsicContentSize()
        }
        renderer.onTapImage = { [weak self] url, alt, rect in
            self?.delegate?.markdownBody(didTapImage: url, altText: alt, sourceRect: rect)
        }
        renderer.onTapVideo = { [weak self] url in self?.delegate?.markdownBody(didTapVideo: url) }
        renderer.onTapAudio = { [weak self] url in self?.delegate?.markdownBody(didTapAudio: url) }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Replaces the rendered content with `blocks`.
    public func setBlocks(_ blocks: [MarkdownBlock]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for view in renderer.views(for: blocks) {
            stack.addArrangedSubview(view)
        }
        indexFootnotes()
    }

    /// The view a footnote link should scroll to, or nil for a non-footnote URL.
    func footnoteTarget(for url: URL) -> UIView? {
        guard let link = MarkdownFootnoteLink(url) else { return nil }
        return targetView(for: link)
    }

    private func targetView(for link: MarkdownFootnoteLink) -> UIView? {
        switch link {
        case let .toDefinition(label): footnoteDefinitionRows[label]
        case let .toReference(label): footnoteReferenceRows[label]
        }
    }

    /// Records which rendered prose view holds each footnote reference / definition
    /// by scanning their link attributes (a `toDefinition` link marks a reference
    /// site; a `toReference` link marks a definition row).
    private func indexFootnotes() {
        footnoteDefinitionRows = [:]
        footnoteReferenceRows = [:]
        for prose in proseViews(in: stack) {
            guard let text = prose.attributedText else { continue }
            text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                guard let url = value as? URL, let link = MarkdownFootnoteLink(url) else { return }
                switch link {
                case let .toDefinition(label):
                    if footnoteReferenceRows[label] == nil { footnoteReferenceRows[label] = prose }
                case let .toReference(label):
                    footnoteDefinitionRows[label] = prose
                }
            }
        }
    }

    private func proseViews(in root: UIView) -> [ProseBlockView] {
        var result: [ProseBlockView] = []
        for sub in root.subviews {
            if let prose = sub as? ProseBlockView {
                result.append(prose)
            } else {
                result.append(contentsOf: proseViews(in: sub))
            }
        }
        return result
    }

    private func scrollToFootnote(_ link: MarkdownFootnoteLink) {
        guard let target = targetView(for: link), let scrollView = enclosingScrollView() else { return }
        let rect = target.convert(target.bounds, to: scrollView).insetBy(dx: 0, dy: -12)
        scrollView.scrollRectToVisible(rect, animated: true)
    }

    private func enclosingScrollView() -> UIScrollView? {
        var view: UIView? = superview
        while let current = view {
            if let scroll = current as? UIScrollView { return scroll }
            view = current.superview
        }
        return nil
    }
}
