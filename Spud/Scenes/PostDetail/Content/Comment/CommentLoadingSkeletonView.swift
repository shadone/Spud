//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A loading placeholder for a post's comments: a column of comment-shaped
/// skeleton rows (a small avatar dot + a short name bar, then two text bars),
/// each indented per depth to read as a threaded tree. Hosted in
/// `PostDetailCommentLoadingCell` as an in-flow row in the comments section while
/// comments load, so it scrolls with content and lands exactly where the comments
/// will appear. The view is self-sizing (its stack is pinned on all four edges),
/// so it drives the cell's height. The pulse and bar factory come from
/// `SkeletonView`.
final class CommentLoadingSkeletonView: SkeletonView {
    /// Indentation depth per skeleton row, to suggest a comment tree.
    private static let rowDepths: [Int] = [0, 0, 1, 2, 0, 1]
    private static let indentPerDepth: CGFloat = 22

    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        for depth in Self.rowDepths {
            stack.addArrangedSubview(makeRow(depth: depth))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeRow(depth: Int) -> UIView {
        let avatar = Self.bar(height: 24)
        avatar.layer.cornerRadius = 12
        NSLayoutConstraint.activate([avatar.widthAnchor.constraint(equalToConstant: 24)])

        let name = Self.bar(height: 12)
        let header = UIStackView(arrangedSubviews: [avatar, name])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        let line1 = Self.bar(height: 12)
        let line2 = Self.bar(height: 12)

        let column = UIStackView(arrangedSubviews: [header, line1, line2])
        column.axis = .vertical
        column.alignment = .leading
        column.spacing = 8

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        column.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(column)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator.withAlphaComponent(0.5)
        container.addSubview(separator)

        let leading = CGFloat(depth) * Self.indentPerDepth + 14

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: container.topAnchor, constant: 11),
            column.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -11),
            column.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leading),
            column.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

            name.widthAnchor.constraint(equalToConstant: 90),
            line1.widthAnchor.constraint(equalTo: column.widthAnchor),
            line2.widthAnchor.constraint(equalTo: column.widthAnchor, multiplier: 0.6),

            separator.heightAnchor.constraint(equalToConstant: 0.5),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
}
