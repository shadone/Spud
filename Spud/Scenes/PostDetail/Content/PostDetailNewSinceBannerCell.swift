//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// In-flow band above the comment list: "N new since your last visit · {time}"
/// with a trailing "Jump" control that scrolls to the first new comment.
final class PostDetailNewSinceBannerCell: UITableViewCell {
    static let reuseIdentifier = "PostDetailNewSinceBannerCell"

    var jumpTapped: (() -> Void)?

    private let dotView = UIView()
    private let messageLabel = UILabel()
    private let jumpButton = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.layer.cornerRadius = 3.5
        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: 7),
            dotView.heightAnchor.constraint(equalToConstant: 7),
        ])

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0

        var config = UIButton.Configuration.plain()
        config.title = NSLocalizedString("Jump", comment: "Jump to the first new comment")
        config.image = UIImage(systemName: "chevron.down")
        config.imagePlacement = .trailing
        config.imagePadding = 3
        config.contentInsets = .zero
        jumpButton.configuration = config
        jumpButton.translatesAutoresizingMaskIntoConstraints = false
        jumpButton.setContentHuggingPriority(.required, for: .horizontal)
        jumpButton.addTarget(self, action: #selector(didTapJump), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [dotView, messageLabel, jumpButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 9
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        jumpTapped = nil
    }

    /// `accent` is the resolved app accent; `count` is the number of new comments;
    /// `relativeText` is e.g. "2 hours ago" (may be nil).
    func configure(count: Int, relativeText: String?, accent: UIColor) {
        dotView.backgroundColor = accent
        contentView.backgroundColor = UIColor { _ in
            accent.withAlphaComponent(
                UITraitCollection.current.userInterfaceStyle == .dark ? 0.16 : 0.11
            )
        }
        jumpButton.tintColor = accent

        let countText = String(
            format: NSLocalizedString("%lld new", comment: "Count of new comments since last visit"),
            count
        )
        let suffix: String = {
            guard let relativeText else {
                return NSLocalizedString(" since your last visit", comment: "New-comments banner suffix without a time")
            }
            return String(
                format: NSLocalizedString(" since your last visit · %@", comment: "New-comments banner suffix with a relative time"),
                relativeText
            )
        }()
        let attr = NSMutableAttributedString(
            string: countText,
            attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline).bold(), .foregroundColor: accent]
        )
        attr.append(NSAttributedString(
            string: suffix,
            attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline), .foregroundColor: UIColor.label]
        ))
        messageLabel.attributedText = attr

        isAccessibilityElement = true
        accessibilityLabel = countText + suffix
        accessibilityTraits = .button
        accessibilityHint = NSLocalizedString("Scrolls to the first new comment", comment: "VoiceOver hint for the new-comments banner")
    }

    override func accessibilityActivate() -> Bool {
        guard jumpTapped != nil else { return false }
        jumpTapped?()
        return true
    }

    @objc
    private func didTapJump() {
        jumpTapped?()
    }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
