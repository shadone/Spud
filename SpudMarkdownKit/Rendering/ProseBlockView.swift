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
