//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// An activity timeline row for a comment: the `ActivityActionHeaderView` verb
/// chip ("You commented · 2h") above a reused `SearchCommentCell` (the existing
/// comment-with-context row), rather than a hand-rolled label stack.
///
/// VoiceOver treats the whole row as one element with a composed label (see
/// `ActivityRowAccessibility`); the inner cell's elements are hidden.
final class ActivityCommentRowCell: UITableViewCell {
    static let reuseIdentifier = "ActivityCommentRowCell"

    private let actionHeader = ActivityActionHeaderView()
    /// The reused search comment cell (body over a context line). Embedded rather
    /// than forked so any future change to comment rendering is shared.
    private let commentCell = SearchCommentCell(style: .default, reuseIdentifier: nil)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        actionHeader.translatesAutoresizingMaskIntoConstraints = false
        commentCell.translatesAutoresizingMaskIntoConstraints = false
        commentCell.contentView.backgroundColor = .clear
        // The embedded comment cell's own disclosure chevron would be redundant
        // (the whole container row is the tap target), so drop it.
        commentCell.accessoryType = .none

        contentView.addSubview(actionHeader)
        contentView.addSubview(commentCell)

        NSLayoutConstraint.activate([
            actionHeader.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            actionHeader.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            actionHeader.trailingAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.trailingAnchor),

            commentCell.topAnchor.constraint(equalTo: actionHeader.bottomAnchor, constant: 2),
            commentCell.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            commentCell.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            commentCell.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        accessibilityLabel = nil
        accessibilityHint = nil
    }

    /// Configures the header, the reused comment cell (body + an Activity-specific
    /// "<community> · <post title>" context line), and the composed VoiceOver
    /// label. `hint` describes the tap action.
    func configure(item: ActivityItem, comment: ActivityCommentRow, hint: String) {
        actionHeader.configure(act: item.act, occurredAt: item.occurredAt)

        let context: String
        if comment.parentPostTitle.isEmpty {
            context = comment.communityName
        } else {
            context = "\(comment.communityName) · \(comment.parentPostTitle)"
        }
        commentCell.configure(content: comment.body, context: context)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = ActivityRowAccessibility.commentLabel(
            act: item.act,
            occurredAt: item.occurredAt,
            comment: comment
        )
        accessibilityHint = hint
        commentCell.accessibilityElementsHidden = true
        actionHeader.accessibilityElementsHidden = true
    }
}
