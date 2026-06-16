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
        renderer.onTapLink = { [weak self] url in self?.delegate?.markdownBody(didTapLink: url) }
        renderer.onContentSizeChange = { [weak self] in
            self?.setNeedsLayout()
            self?.invalidateIntrinsicContentSize()
        }
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
    }
}
