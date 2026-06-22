//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The "No comments yet" placeholder shown in a post's comments region once a
/// comment fetch settles with no comments. A plain view used as the table
/// background, so it sits below the post header rather than overlaying it the way
/// `UIContentUnavailableConfiguration` would.
final class PostDetailEmptyCommentsView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

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

        let title = UILabel()
        title.text = titleText
        title.font = .preferredFont(forTextStyle: .headline)
        title.textColor = .secondaryLabel
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = subtitleText
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.textColor = .tertiaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(12, after: icon)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
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
