//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A list (ordered or unordered) rendered as a vertical stack of items; each
/// item is a marker beside an indented stack of its child block views, so
/// nested lists and multi-block items render correctly.
final class ListBlockView: UIView {
    init(
        items: [MarkdownListItem],
        ordered: Bool,
        start: Int,
        depth: Int,
        context: MarkdownContext,
        renderer: MarkdownBlockRenderer
    ) {
        super.init(frame: .zero)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = context.kind == .post ? 5 : 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        for (i, item) in items.enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 6

            let marker = UILabel()
            marker.text = ordered ? "\(start + i)." : (depth % 2 == 0 ? "\u{2022}" : "\u{25E6}")
            marker.font = context.bodyFont
            marker.textColor = context.secondaryColor
            marker.setContentHuggingPriority(.required, for: .horizontal)
            marker.widthAnchor.constraint(equalToConstant: context.listIndent).isActive = true
            marker.textAlignment = .left

            let content = UIStackView()
            content.axis = .vertical
            content.spacing = context.kind == .post ? 5 : 3
            for child in itemViews(item, depth: depth, context: context, renderer: renderer) {
                content.addArrangedSubview(child)
            }

            row.addArrangedSubview(marker)
            row.addArrangedSubview(content)
            stack.addArrangedSubview(row)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Renders an item's blocks; a nested list recurses with `depth + 1`.
    private func itemViews(
        _ item: MarkdownListItem,
        depth: Int,
        context: MarkdownContext,
        renderer: MarkdownBlockRenderer
    ) -> [UIView] {
        item.blocks.map { block in
            switch block {
            case let .unorderedList(sub):
                return ListBlockView(
                    items: sub,
                    ordered: false,
                    start: 1,
                    depth: depth + 1,
                    context: context,
                    renderer: renderer
                )
            case let .orderedList(s, sub):
                return ListBlockView(
                    items: sub,
                    ordered: true,
                    start: s,
                    depth: depth + 1,
                    context: context,
                    renderer: renderer
                )
            default:
                return renderer.view(for: block)
            }
        }
    }
}
