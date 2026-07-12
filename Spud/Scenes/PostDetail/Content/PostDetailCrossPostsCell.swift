//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUtilKit
import UIKit

/// In-flow "Cross-posted to N communities" section on the post-detail header:
/// a small title followed by one tappable row per cross-post, each showing its
/// community's "c/name@instance" handle and a light score/comment-count line.
///
/// One cell renders every cross-post (there is exactly one `.crossPostedTo`
/// diffable item — see `PostDetailViewController.applySnapshot()`), so the row
/// list is rebuilt from scratch on each `configure(with:)` rather than being a
/// nested diffable/table structure of its own.
final class PostDetailCrossPostsCell: UITableViewCell {
    static let reuseIdentifier = "PostDetailCrossPostsCell"

    /// Invoked with the tapped cross-post's summary.
    var crossPostTapped: ((CrossPostSummary) -> Void)?

    private let titleLabel = UILabel()
    private let rowsStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .footnote)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel
        titleLabel.numberOfLines = 0

        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.axis = .vertical
        rowsStack.spacing = 0

        let container = UIStackView(arrangedSubviews: [titleLabel, rowsStack])
        container.translatesAutoresizingMaskIntoConstraints = false
        container.axis = .vertical
        container.spacing = 8

        contentView.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        crossPostTapped = nil
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    /// Rebuilds the title + row list for `crossPosts`, in the given (server)
    /// order. A no-op call with an empty array leaves an empty section — the
    /// view controller only puts this item in the snapshot when there is at
    /// least one cross-post, so that path is defensive rather than expected.
    func configure(with crossPosts: [CrossPostSummary]) {
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let count = crossPosts.count
        titleLabel.text = count == 1
            ? NSLocalizedString(
                "Cross-posted to 1 community",
                comment: "Post-detail cross-posts section title, singular"
            )
            : String(
                format: NSLocalizedString(
                    "Cross-posted to %lld communities",
                    comment: "Post-detail cross-posts section title, with a community count"
                ),
                count
            )

        for (index, summary) in crossPosts.enumerated() {
            let row = CrossPostRowControl()
            row.configure(with: summary)
            row.addAction(UIAction { [weak self] _ in self?.crossPostTapped?(summary) }, for: .touchUpInside)
            rowsStack.addArrangedSubview(row)

            if index < crossPosts.count - 1 {
                let divider = UIView()
                divider.backgroundColor = .separator
                // `UIScreen.main` is soft-deprecated; fall back to 1x only in the
                // (untappable in practice) case the cell isn't in a window yet.
                let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
                divider.heightAnchor.constraint(equalToConstant: 1 / scale).isActive = true
                rowsStack.addArrangedSubview(divider)
            }
        }
    }
}

/// One tappable cross-post row: a "c/community@instance" handle, a light
/// score/comment-count line, and a trailing disclosure chevron.
///
/// A `UIControl` (not a `UIButton.Configuration`-based button): the
/// leading-content + trailing-chevron layout needs to spread across the row's
/// full width, which `UIButton.Configuration`'s title/image packing doesn't do
/// on its own, and a plain `UIControl` gives a standard list-row tap highlight
/// (a background tint toggled on touch-down/up, matching a normal table row)
/// rather than a button's dimming.
private final class CrossPostRowControl: UIControl {
    private let handleLabel = UILabel()
    private let metadataLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))

    override init(frame: CGRect) {
        super.init(frame: frame)

        handleLabel.translatesAutoresizingMaskIntoConstraints = false
        handleLabel.font = .preferredFont(forTextStyle: .subheadline)
        handleLabel.adjustsFontForContentSizeCategory = true
        handleLabel.textColor = .label
        handleLabel.lineBreakMode = .byTruncatingTail

        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = .preferredFont(forTextStyle: .caption1)
        metadataLabel.adjustsFontForContentSizeCategory = true
        metadataLabel.textColor = .secondaryLabel

        let textStack = UIStackView(arrangedSubviews: [handleLabel, metadataLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2
        // The labels are purely visual; the whole row is one accessibility
        // element (below) and one tap target, so touches must pass through to
        // the control rather than the stack intercepting them.
        textStack.isUserInteractionEnabled = false

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .tertiaryLabel
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevron.isUserInteractionEnabled = false

        addSubview(textStack)
        addSubview(chevron)
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            chevron.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 8),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .link

        addTarget(self, action: #selector(highlightOn), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(highlightOff), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with summary: CrossPostSummary) {
        let handle = summary.qualifiedCommunityHandle
        handleLabel.text = handle

        let metadata = "\(Self.pointsText(for: summary.score)) · \(Self.commentsText(for: summary.commentCount))"
        metadataLabel.text = metadata

        accessibilityLabel = String(
            format: NSLocalizedString(
                "Open cross-post in %@",
                comment: "VoiceOver label for a cross-post row; %@ is the community handle"
            ),
            handle
        )
        accessibilityValue = metadata
    }

    @objc
    private func highlightOn() {
        backgroundColor = .tertiarySystemFill
    }

    @objc
    private func highlightOff() {
        backgroundColor = .clear
    }

    /// Singular/plural score text, e.g. "1 point" / "128 points" (compact-
    /// formatted for large scores via `CountFormatter`). Hand-rolled, matching
    /// `PostDetailCrossPostsCell`'s section-title singular/plural approach —
    /// the codebase has no stringsdict convention.
    private static func pointsText(for score: Int64) -> String {
        score == 1
            ? NSLocalizedString(
                "1 point",
                comment: "Cross-post row metadata: score, singular"
            )
            : String(
                format: NSLocalizedString(
                    "%@ points",
                    comment: "Cross-post row metadata: score, with a compact count"
                ),
                CountFormatter.string(score)
            )
    }

    /// Singular/plural comment-count text, e.g. "1 comment" / "42 comments".
    private static func commentsText(for commentCount: Int64) -> String {
        commentCount == 1
            ? NSLocalizedString(
                "1 comment",
                comment: "Cross-post row metadata: comment count, singular"
            )
            : String(
                format: NSLocalizedString(
                    "%@ comments",
                    comment: "Cross-post row metadata: comment count, with a compact count"
                ),
                CountFormatter.string(commentCount)
            )
    }
}
