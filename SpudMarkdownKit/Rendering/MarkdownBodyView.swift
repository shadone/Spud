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

    /// Called after `invalidateIntrinsicContentSize()` when an inline image load
    /// changes the body height, giving the enclosing table cell a hook to
    /// re-measure the row WITHOUT animation. The image view has never been laid
    /// out at this point, so an animated re-measure would interpolate its frame
    /// from `.zero` — visible as the image zooming in from a corner.
    public var onContentSizeChange: (() -> Void)?

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
        renderer.onLinkMenu = { [weak self] url in
            guard let self else { return nil }
            // A footnote jump has no useful long-press menu, and its synthetic URL
            // isn't a link the host knows how to classify — suppress the menu (nil)
            // rather than hand it over. Everything else goes to the host.
            if MarkdownFootnoteLink(url) != nil { return nil }
            return delegate?.markdownBody(menuConfigurationForLink: url)
        }
        renderer.onContentSizeChange = { [weak self] in
            self?.setNeedsLayout()
            self?.invalidateIntrinsicContentSize()
            self?.onContentSizeChange?()
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

    // MARK: Tap hit-testing (for the comment collapse-tap deferral)

    /// Whether `point` (in this view's own coordinate space) lands on something the
    /// body handles itself: a link range inside prose text, a media tile
    /// (image/audio/video), or an interactive control (e.g. a code block's copy
    /// button). Hosts that overlay their own tap gesture (the comment collapse-tap)
    /// call this to defer to the body's own tap handling instead of collapsing.
    /// Plain body text and plain block chrome return `false`.
    public func handlesTap(at point: CGPoint) -> Bool {
        handlesTap(at: point, in: self)
    }

    /// Recursively walks `view`'s subviews looking for the first interactive
    /// target under `point` (given in `view`'s coordinate space). Prose views are
    /// asked via `hasLink(at:)` but never descended into (a `UITextView` has
    /// internal subviews that would mis-fire); media tiles and controls are
    /// always interactive; structural containers (lists, quotes, tables,
    /// spoilers, footnotes — including the private stack) fall through to the
    /// recursive branch, so links inside them (e.g. footnote back-link ranges
    /// in `FootnotesBlockView`'s prose children) are still found.
    private func handlesTap(at point: CGPoint, in view: UIView) -> Bool {
        for subview in view.subviews {
            if subview.isHidden { continue }
            let converted = view.convert(point, to: subview)
            guard subview.bounds.contains(converted) else { continue }

            if let prose = subview as? ProseBlockView {
                if prose.hasLink(at: converted) { return true }
                // Do not recurse into a UITextView's internal subviews.
                continue
            }
            if subview is ImageBlockView || subview is AudioBlockView || subview is VideoBlockView {
                return true
            }
            if subview is UIControl {
                return true
            }
            // A view that installed its own tap recognizer handles the tap itself
            // (e.g. a spoiler's disclosure header), so defer to it rather than collapse.
            if subview.gestureRecognizers?.contains(where: { $0 is UITapGestureRecognizer }) == true {
                return true
            }
            if handlesTap(at: converted, in: subview) {
                return true
            }
        }
        return false
    }
}
