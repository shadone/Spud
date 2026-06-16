//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A blockquote: a colored leading bar and an inset vertical stack of child
/// block views. Nesting is achieved by placing a `QuoteBlockView` inside another.
final class QuoteBlockView: UIView {
    private let stack = UIStackView()

    init(context: MarkdownContext) {
        super.init(frame: .zero)
        let bar = UIView()
        bar.backgroundColor = context.quoteBarColor
        bar.layer.cornerRadius = 1.5
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)

        stack.axis = .vertical
        stack.spacing = context.interBlockGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let barWidth: CGFloat = context.kind == .post ? 3 : 2.5
        let inset: CGFloat = context.kind == .post ? 13 : 10
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: barWidth),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func addArrangedChild(_ view: UIView) {
        stack.addArrangedSubview(view)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}
