//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A non-editable, non-scrolling, self-sizing text view for one attributed string
/// (a paragraph/heading run, or a list/quote leaf). Built on an explicit TextKit 1
/// stack so a `ChipBackgroundLayoutManager` can paint rounded mention/community
/// pills behind the handle text.
final class ProseBlockView: UITextView {
    var onTapLink: ((URL) -> Void)?

    /// Builds the long-press context menu for an inline link, or `nil` to show
    /// no menu. Mirrors `onTapLink`: the host resolves the URL and returns a menu
    /// that is safe for the link's scheme (never UIKit's default, which traps on
    /// a non-`http(s)` link preview). See `textView(_:menuConfigurationFor:defaultMenu:)`.
    var onLinkMenu: ((URL) -> UITextItem.MenuConfiguration?)?

    /// Strongly held so the manual TextKit 1 stack isn't torn down.
    private let chipTextStorage: NSTextStorage

    init() {
        let textStorage = NSTextStorage()
        let layoutManager = ChipBackgroundLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        chipTextStorage = textStorage

        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isScrollEnabled = false
        isSelectable = true
        backgroundColor = .clear
        textContainerInset = .zero
        adjustsFontForContentSizeCategory = true
        // Defer link styling to the attributed string so links/mentions/footnote
        // refs keep their brand-teal color instead of UIKit's blue tint override.
        linkTextAttributes = [:]
        delegate = self
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: Link hit-testing (for the comment collapse-tap deferral)

    /// Whether `point` (in this view's own coordinate space) lands on a tappable
    /// link range: enumerates `.link` attributes and tests their selection rects
    /// against `point`. Plain text (no `.link` attribute under the point) returns
    /// `false`.
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
}

extension ProseBlockView: UITextViewDelegate {
    func textView(
        _: UITextView,
        primaryActionFor textItem: UITextItem,
        defaultAction: UIAction
    ) -> UIAction? {
        if case let .link(url) = textItem.content {
            return UIAction { [weak self] _ in self?.onTapLink?(url) }
        }
        return defaultAction
    }

    /// The context menu for a long-press on a text item.
    ///
    /// For a LINK we must never let UIKit's default menu run: its default menu
    /// eagerly builds a URL preview that TRAPS when the link's scheme is not
    /// `http(s)` — the synthetic `spud-markdown://mention?…` URL a Lemmy mention
    /// renders as crashes here. So we always take over the link case and forward
    /// to `onLinkMenu`; when the host provides no hook, or declines (returns
    /// `nil`), we return `nil` to SUPPRESS the menu. Returning `nil` here is
    /// verified-safe: `UITextViewDelegate` documents it as "prevent the menu from
    /// being presented" — it does NOT fall back to the crashing default.
    ///
    /// Non-link text items (attachments/tags) keep UIKit's default menu, mirroring
    /// how `primaryActionFor` returns `defaultAction` for non-links.
    func textView(
        _: UITextView,
        menuConfigurationFor textItem: UITextItem,
        defaultMenu: UIMenu
    ) -> UITextItem.MenuConfiguration? {
        guard case let .link(url) = textItem.content else {
            return UITextItem.MenuConfiguration(menu: defaultMenu)
        }
        return onLinkMenu?(url)
    }
}
