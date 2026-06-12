//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import UIKit

/// The keyboard accessory toolbar of markdown formatting buttons. Lays the
/// actions out in a horizontally-scrolling row so the full set fits on narrow
/// devices, and forwards taps to its `onAction` callback. Reused by every
/// markdown editor (comment/DM composer and the new-post body editor).
final class MarkdownToolbar: UIInputView {
    /// Invoked with the chosen action when the user taps a formatting button.
    var onAction: ((MarkdownFormatting.Action) -> Void)?

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        return scrollView
    }()

    private lazy var stackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.layoutMargins = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.isLayoutMarginsRelativeArrangement = true
        return stack
    }()

    init() {
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: 48),
            inputViewStyle: .keyboard
        )
        allowsSelfSizing = false
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        scrollView.addSubview(stackView)

        for descriptor in Self.descriptors {
            stackView.addArrangedSubview(makeButton(for: descriptor))
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeButton(for descriptor: Descriptor) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: descriptor.symbolName)
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)

        let button = UIButton(configuration: config)
        button.accessibilityLabel = descriptor.accessibilityLabel
        let action = descriptor.action
        button.addAction(UIAction { [weak self] _ in
            self?.onAction?(action)
        }, for: .touchUpInside)
        return button
    }

    // MARK: Action descriptors

    private struct Descriptor {
        let action: MarkdownFormatting.Action
        let symbolName: String
        let accessibilityLabel: String
    }

    private static let descriptors: [Descriptor] = [
        .init(action: .bold, symbolName: "bold", accessibilityLabel: NSLocalizedString("Bold", comment: "Markdown toolbar action")),
        .init(action: .italic, symbolName: "italic", accessibilityLabel: NSLocalizedString("Italic", comment: "Markdown toolbar action")),
        .init(action: .strikethrough, symbolName: "strikethrough", accessibilityLabel: NSLocalizedString("Strikethrough", comment: "Markdown toolbar action")),
        .init(action: .link, symbolName: "link", accessibilityLabel: NSLocalizedString("Link", comment: "Markdown toolbar action")),
        .init(action: .quote, symbolName: "text.quote", accessibilityLabel: NSLocalizedString("Quote", comment: "Markdown toolbar action")),
        .init(action: .unorderedList, symbolName: "list.bullet", accessibilityLabel: NSLocalizedString("Bulleted list", comment: "Markdown toolbar action")),
        .init(action: .orderedList, symbolName: "list.number", accessibilityLabel: NSLocalizedString("Numbered list", comment: "Markdown toolbar action")),
        .init(action: .code, symbolName: "chevron.left.forwardslash.chevron.right", accessibilityLabel: NSLocalizedString("Inline code", comment: "Markdown toolbar action")),
        .init(action: .codeBlock, symbolName: "curlybraces", accessibilityLabel: NSLocalizedString("Code block", comment: "Markdown toolbar action")),
        .init(action: .spoiler, symbolName: "eye.slash", accessibilityLabel: NSLocalizedString("Spoiler", comment: "Markdown toolbar action")),
    ]
}
