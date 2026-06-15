//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUtilKit
import UIKit

/// A non-editable, non-scrolling, self-sizing `UITextView` used to render a post
/// or comment body. It replaces `LinkLabel` for bodies because, unlike a label,
/// a real text view lays out and hit-tests through one TextKit engine — so inline
/// image attachments (`BodyImageAttachment`) draw, size, and reflow correctly.
///
/// The host-facing API mirrors `LinkLabel` (`attributedText`, `tapped`,
/// `hasLink(at:)`) so call sites change little. Inline images are loaded here:
/// when the body is assigned, each `BodyImageAttachment` is swapped for a fresh
/// per-view copy (so the shared `MarkdownRenderer` cache is never mutated), then
/// loaded via `imageService`; once an image arrives the run is re-laid-out and
/// `onContentSizeChange` fires so the enclosing table row re-measures.
final class BodyTextView: UITextView {
    /// The image loader used for inline images. Must be set before assigning a
    /// body that contains images.
    var imageService: ImageServiceType?

    /// Fired when a body link (or inline image) is tapped, with its URL.
    var tapped: ((URL) -> Void)?

    /// Fired when the rendered size changes after an inline image loads, so the
    /// host (a table) can re-measure the row.
    var onContentSizeChange: (() -> Void)?

    /// The maximum height an inline image may occupy.
    var maxImageHeight: CGFloat = 400

    private var loadTasks: [Task<Void, Never>] = []

    // MARK: Init

    init() {
        // Force TextKit 2 (the default on iOS 16+); never touch `layoutManager`,
        // which would silently drop the text view to TextKit 1.
        super.init(frame: .zero, textContainer: nil)

        isEditable = false
        isScrollEnabled = false
        isSelectable = true
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        dataDetectorTypes = []
        // Match LinkLabel: links underline; their colour comes from the rendered
        // attributed string (the styler sets it).
        linkTextAttributes = [.underlineStyle: NSUnderlineStyle.single.rawValue]
        adjustsFontForContentSizeCategory = true
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for task in loadTasks {
            task.cancel()
        }
    }

    // MARK: Body assignment

    override var attributedText: NSAttributedString! {
        get { super.attributedText }
        set { configureBody(newValue) }
    }

    private func configureBody(_ newValue: NSAttributedString?) {
        cancelLoads()

        guard let newValue, newValue.length > 0 else {
            super.attributedText = newValue
            return
        }

        // Swap each shared, cached image attachment for a fresh per-view copy so
        // loading state (the image, aspect ratio) never mutates the cache or
        // races another text view.
        let fullRange = NSRange(location: 0, length: newValue.length)
        var originals: [(BodyImageAttachment, NSRange)] = []
        newValue.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            if let attachment = value as? BodyImageAttachment {
                originals.append((attachment, range))
            }
        }

        guard !originals.isEmpty else {
            super.attributedText = newValue
            return
        }

        let mutable = NSMutableAttributedString(attributedString: newValue)
        var copies: [BodyImageAttachment] = []
        for (original, range) in originals {
            let copy = original.displayCopy()
            copy.maxDisplayHeight = maxImageHeight
            mutable.removeAttribute(.attachment, range: range)
            mutable.addAttribute(.attachment, value: copy, range: range)
            copies.append(copy)
        }
        super.attributedText = mutable

        if let imageService {
            for copy in copies {
                startLoading(copy, imageService: imageService)
            }
        }
    }

    private func cancelLoads() {
        for task in loadTasks {
            task.cancel()
        }
        loadTasks.removeAll()
    }

    private func startLoading(_ attachment: BodyImageAttachment, imageService: ImageServiceType) {
        let url = attachment.imageURL
        let task = Task { @MainActor [weak self, weak attachment] in
            for await state in imageService.fetch(url) {
                guard let self, let attachment else { return }
                switch state {
                case .loading:
                    continue
                case let .ready(image):
                    attachment.image = image
                    let size = image.size
                    if size.width > 0, size.height > 0 {
                        attachment.aspectRatio = size.width / size.height
                    }
                    reflowAfterImageChange()
                case .failure:
                    let placeholder = Self.failurePlaceholder
                    attachment.image = placeholder
                    let size = placeholder.size
                    attachment.aspectRatio = size.height > 0 ? size.width / size.height : nil
                    reflowAfterImageChange()
                }
            }
        }
        loadTasks.append(task)
    }

    /// Re-lay-out so the attachment reflows to its now-known size, then ask the
    /// host to re-measure.
    private func reflowAfterImageChange() {
        if let textLayoutManager {
            textLayoutManager.invalidateLayout(for: textLayoutManager.documentRange)
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        setNeedsDisplay()
        onContentSizeChange?()
    }

    // MARK: Link hit-testing (for the comment collapse-tap deferral)

    /// Whether `point` (in this view's coordinate space) lands on a tappable link
    /// or inline image. The comment cell uses this to avoid collapsing a thread
    /// when the tap was actually on a link/image.
    func hasLink(at point: CGPoint) -> Bool {
        guard let attributed = attributedText, attributed.length > 0 else { return false }

        var hit = false
        attributed.enumerateAttribute(.link, in: NSRange(location: 0, length: attributed.length)) { value, range, stop in
            guard value != nil else { return }
            if rects(for: range).contains(where: { $0.contains(point) }) {
                hit = true
                stop.pointee = true
            }
        }
        return hit
    }

    private func rects(for range: NSRange) -> [CGRect] {
        guard
            let start = position(from: beginningOfDocument, offset: range.location),
            let end = position(from: start, offset: range.length),
            let textRange = textRange(from: start, to: end)
        else {
            return []
        }
        return selectionRects(for: textRange).map(\.rect).filter { $0.width > 0 && $0.height > 0 }
    }

    // MARK: Failure placeholder

    /// A small inline "broken image" tile shown when a body image fails to load.
    /// The attachment keeps its `.link`, so it remains tappable (it opens the URL
    /// in the viewer / browser).
    private static let failurePlaceholder: UIImage = {
        let size = CGSize(width: 200, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.secondarySystemFill.setFill()
            let bg = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10)
            bg.fill()
            let config = UIImage.SymbolConfiguration(pointSize: 36, weight: .regular)
            if let glyph = UIImage(systemName: "photo", withConfiguration: config)?
                .withTintColor(.tertiaryLabel, renderingMode: .alwaysOriginal)
            {
                let origin = CGPoint(
                    x: (size.width - glyph.size.width) / 2,
                    y: (size.height - glyph.size.height) / 2
                )
                glyph.draw(at: origin)
            }
            _ = context
        }
    }()
}

// MARK: - UITextViewDelegate

extension BodyTextView: UITextViewDelegate {
    func textView(
        _: UITextView,
        primaryActionFor textItem: UITextItem,
        defaultAction: UIAction
    ) -> UIAction? {
        switch textItem.content {
        case let .link(url):
            return UIAction { [weak self] _ in self?.tapped?(url) }
        case let .textAttachment(attachment):
            if let body = attachment as? BodyImageAttachment {
                return UIAction { [weak self] _ in self?.tapped?(body.imageURL) }
            }
            return defaultAction
        default:
            return defaultAction
        }
    }

    /// Suppress the native long-press menu for internal-scheme links (Lemmy
    /// mentions become opaque `info.ddenis.spud://` URLs that mean nothing to the
    /// user). Web links keep the default menu (Open / Copy / Share).
    func textView(
        _: UITextView,
        menuConfigurationFor textItem: UITextItem,
        defaultMenu: UIMenu
    ) -> UITextItem.MenuConfiguration? {
        if case let .link(url) = textItem.content, url.spud != nil {
            return nil
        }
        return UITextItem.MenuConfiguration(menu: defaultMenu)
    }
}
