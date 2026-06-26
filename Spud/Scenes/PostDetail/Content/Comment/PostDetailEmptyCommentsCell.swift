//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// In-flow "No comments yet" empty-state row, shown in the comments section once a
/// comment fetch settles with no comments. Rendered as a row below the post header
/// (and scrolling with it) rather than as a centered table background, so the pinned
/// header never obscures it. Self-sizing: the icon/title/subtitle stack is pinned to
/// the content view top and bottom (with vertical padding), so the cell takes its
/// natural height. The table's separator is suppressed for this row.
final class PostDetailEmptyCommentsCell: UITableViewCell {
    static let reuseIdentifier = "PostDetailEmptyCommentsCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none
        backgroundColor = .clear

        // Empty-state row draws no separator; push the line off the leading edge.
        separatorInset = UIEdgeInsets(top: 0, left: .greatestFiniteMagnitude, bottom: 0, right: 0)

        let titleText = NSLocalizedString(
            "No comments yet",
            comment: "Empty-state title for a post with no comments"
        )
        let subtitleText = NSLocalizedString(
            "Be the first to comment.",
            comment: "Empty-state subtitle for a post with no comments"
        )

        let icon = UIImageView(image: UIImage(systemName: "text.bubble"))
        icon.tintColor = .tertiaryLabel
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        icon.adjustsImageSizeForAccessibilityContentSizeCategory = true

        let title = UILabel()
        title.text = titleText
        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = .secondaryLabel
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = subtitleText
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.textColor = .tertiaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(12, after: icon)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 48),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -32),
        ])

        isAccessibilityElement = true
        accessibilityLabel = "\(titleText). \(subtitleText)"
        accessibilityTraits = .staticText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
