//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A non-editable, non-scrolling, self-sizing TextKit 2 text view for one
/// attributed string (a paragraph/heading run, or a list/quote leaf).
final class ProseBlockView: UITextView {
    var onTapLink: ((URL) -> Void)?

    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        isScrollEnabled = false
        isSelectable = true
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        adjustsFontForContentSizeCategory = true
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
}
