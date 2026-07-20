//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Full-width notice shown below the post body in `PostDetailHeaderCell` when
/// the post is locked: new comments/replies are turned off, but voting is
/// still allowed. Copy comes entirely from `CommentLockPolicy` — the single
/// source of truth for locked-post wording — never hardcode it here.
///
/// A rounded `secondarySystemBackground` card with a leading `lock.fill`
/// glyph, a headline-weight title, and a secondary footnote message. Hidden by
/// default (contributing no height in the enclosing stack view) so an
/// unlocked post's header renders unchanged; the owning cell toggles
/// `isHidden` from `PostDetailHeaderViewModel.isLocked` on every reconfigure —
/// this view never caches the locked state itself.
final class LockedCommentsNoticeView: UIView {
    private let iconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "lock.fill"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .secondaryLabel
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        // Decorative: the notice speaks as a single combined accessibility
        // element (see `accessibilityLabel` below), not per-glyph.
        imageView.isAccessibilityElement = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 0
        return label
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: .systemFont(ofSize: 13))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 12
        clipsToBounds = true
        accessibilityIdentifier = "lockedCommentsNotice"

        let textStack = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2

        let contentStack = UIStackView(arrangedSubviews: [iconView, textStack])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .horizontal
        contentStack.alignment = .top
        contentStack.spacing = 10
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])

        titleLabel.text = CommentLockPolicy.title
        messageLabel.text = CommentLockPolicy.message

        // One combined element, not a control: this is informational with no
        // action to trigger, mirroring the folded author-status pill row.
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = "\(CommentLockPolicy.title). \(CommentLockPolicy.message)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
