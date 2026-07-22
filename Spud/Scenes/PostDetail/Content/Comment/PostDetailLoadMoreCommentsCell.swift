//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Terminal "Load more comments" row, appended to the comments section when a
/// fetch stopped with pages still outstanding (``PostDetailViewModel/hasOutstandingCommentPages``).
/// Rendered as an in-flow row below the loaded comments (not a table footer),
/// mirroring ``PostDetailEmptyCommentsCell`` / ``PostDetailCommentsFailedCell``.
///
/// Unlike those sibling placeholders the row IS interactive, but deliberately has
/// no nested button: the tap is driven by the table view's own row selection
/// (`tableView(_:didSelectRowAt:)`), which sidesteps the hit-testing trap a
/// button nested in a conditionally-disabled superview can fall into (see the
/// project's accessibility notes). `titleLabel` uses the same link-like
/// treatment (`UIColor.link`) the "N more replies" row uses, and both it and the
/// loading spinner inherit their font from `UIFont.preferredFont(forTextStyle:)`
/// with `adjustsFontForContentSizeCategory` -- Dynamic Type and light/dark both
/// fall out of using semantic system values instead of fixed ones.
final class PostDetailLoadMoreCommentsCell: UITableViewCell {
    static let reuseIdentifier = "PostDetailLoadMoreCommentsCell"

    private static let title = NSLocalizedString(
        "Load more comments",
        comment: "Terminal row tapped to fetch the next batch of a comment listing that stopped partway through"
    )
    private static let loadingHint = NSLocalizedString(
        "Loading",
        comment: "VoiceOver hint while more comments load"
    )
    private static let loadHint = NSLocalizedString(
        "Loads more comments",
        comment: "VoiceOver hint for the load-more-comments row"
    )

    private let titleLabel = UILabel()
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        // Selection IS the tap affordance here (no nested button), so the row
        // keeps the system highlight instead of the `.none` its non-interactive
        // siblings use.
        selectionStyle = .default
        backgroundColor = .clear

        // Matches the empty/failed sibling rows: no separator under an in-flow
        // placeholder row.
        separatorInset = UIEdgeInsets(top: 0, left: .greatestFiniteMagnitude, bottom: 0, right: 0)

        titleLabel.text = Self.title
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .link
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -32),

            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        applyAccessibility(isLoading: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        setLoading(false)
    }

    /// Swaps the "Load more comments" label for an inline spinner while a fetch
    /// is in flight. The row's `accessibilityTraits` drop `.button` while
    /// loading (mirroring the sibling comment cell's "load more replies" row)
    /// so VoiceOver doesn't invite a second tap on a request that's already
    /// running.
    func setLoading(_ isLoading: Bool) {
        titleLabel.isHidden = isLoading
        if isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
        applyAccessibility(isLoading: isLoading)
    }

    private func applyAccessibility(isLoading: Bool) {
        accessibilityLabel = isLoading ? Self.loadingHint : Self.title
        accessibilityHint = isLoading ? Self.loadingHint : Self.loadHint
        accessibilityTraits = isLoading ? [] : .button
    }
}
