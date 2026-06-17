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
