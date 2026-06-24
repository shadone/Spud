//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// In-flow comment-loading row: hosts a `CommentLoadingSkeletonView` pinned to the
/// content view on all four edges, so the cell self-sizes to the skeleton's
/// height. Rendered as a row in the comments section (below the header) while
/// comments load, so it scrolls with content and lands where the comments will
/// appear. The skeleton draws its own internal separators, so the table's own
/// single-line separator is suppressed for this row.
final class PostDetailCommentLoadingCell: UITableViewCell {
    static let reuseIdentifier = "PostDetailCommentLoadingCell"

    private let skeletonView = CommentLoadingSkeletonView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none
        backgroundColor = .clear

        // The table uses its default single-line separators; push this row's
        // separator off the leading edge so no stray line shows under the
        // skeleton (which draws its own internal separators).
        separatorInset = UIEdgeInsets(top: 0, left: .greatestFiniteMagnitude, bottom: 0, right: 0)

        skeletonView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(skeletonView)
        NSLayoutConstraint.activate([
            skeletonView.topAnchor.constraint(equalTo: contentView.topAnchor),
            skeletonView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            skeletonView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            skeletonView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        skeletonView.stopAnimating()
        super.prepareForReuse()
    }

    func startAnimating() {
        skeletonView.startAnimating()
    }
}
