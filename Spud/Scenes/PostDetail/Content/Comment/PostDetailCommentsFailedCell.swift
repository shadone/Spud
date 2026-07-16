//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

/// In-flow "couldn't load comments" row, shown in the comments section when the
/// initial comment fetch fails and there are no comments to show. Rendered as a
/// row below the post header (and scrolling with it) rather than a centered table
/// background, mirroring ``PostDetailEmptyCommentsCell`` — so the pinned header
/// never obscures it.
///
/// This replaces the misleading "No comments yet" empty state for a failed fetch:
/// after going offline the user gets a truthful "You're offline" / "Couldn't
/// reach the server" message and a Retry button, not a false "be the first to
/// comment". Copy and glyph are reused from ``FeedStatePresenter`` so the
/// comments offline surface matches the feed's tone verbatim.
///
/// Self-sizing: the icon/title/subtitle/Retry stack is pinned to the content view
/// top and bottom (with vertical padding), so the cell takes its natural height.
/// The table's separator is suppressed for this row.
final class PostDetailCommentsFailedCell: UITableViewCell {
    static let reuseIdentifier = "PostDetailCommentsFailedCell"

    /// Invoked when the user taps Retry. The view controller re-runs the comment
    /// fetch. Reset on reuse.
    var onRetry: (() -> Void)?

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let retryButton: UIButton

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        retryButton = UIButton(configuration: .borderedProminent())
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none
        backgroundColor = .clear

        // Failed-state row draws no separator; push the line off the leading edge.
        separatorInset = UIEdgeInsets(top: 0, left: .greatestFiniteMagnitude, bottom: 0, right: 0)

        iconView.tintColor = .tertiaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        iconView.adjustsImageSizeForAccessibilityContentSizeCategory = true

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .tertiaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        retryButton.accessibilityIdentifier = "commentsRetry"

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, subtitleLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(12, after: iconView)
        stack.setCustomSpacing(16, after: subtitleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 48),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -32),
        ])

        // Default reading order including Retry; `configure(with:)` narrows this
        // to omit the button for a non-retriable failure.
        accessibilityElements = [titleLabel, subtitleLabel, retryButton]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onRetry = nil
    }

    /// Configures the row from a classified ``LoadFailure``. Copy and glyph reuse
    /// ``FeedStatePresenter`` so the message matches the feed's offline/unreachable
    /// wording; the comments fetch has no instance host to interpolate, so the
    /// `unreachable`/`malformedResponse` host-aware variant falls back to the
    /// generic "the server" phrasing.
    ///
    /// `descriptor.primary` is `nil` for the non-retriable `.notSupported` kind
    /// (a capability-gated comment fetch, e.g. on an instance/dialect that
    /// doesn't support it) — the Retry button hides in that case, since a retry
    /// can never succeed, and drops out of the VoiceOver reading order with it.
    func configure(with failure: LoadFailure) {
        let descriptor = FeedStatePresenter.descriptor(for: failure.kind, host: nil)
        iconView.image = UIImage(systemName: descriptor.symbolName)
        titleLabel.text = descriptor.title
        subtitleLabel.text = descriptor.message

        if let primary = descriptor.primary {
            retryButton.isHidden = false
            retryButton.configuration?.title = primary.title
            retryButton.configuration?.baseBackgroundColor = ThemeManager.currentAccentColor
            accessibilityElements = [titleLabel, subtitleLabel, retryButton]
        } else {
            retryButton.isHidden = true
            accessibilityElements = [titleLabel, subtitleLabel]
        }
    }

    @objc
    private func retryTapped() {
        onRetry?()
    }
}
