//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// An activity timeline row for a comment: the `ActivityActionHeaderView` verb
/// chip ("You commented · 2h") above a reused `SearchCommentContentView` (the
/// existing comment-with-context rendering), rather than a hand-rolled label
/// stack.
///
/// The comment rendering is the SHARED `SearchCommentContentView` — the same view
/// the Search results cell hosts — so any future change to comment rendering is
/// shared. Critically it is a plain content `UIView`, not a nested
/// `UITableViewCell`: a nested cell's own `contentView` is attached by
/// autoresizing mask, which severs the Auto Layout height chain and collapses the
/// embedded content to ~0pt. Hosting the content view directly lets its intrinsic
/// height drive the row.
///
/// VoiceOver treats the whole row as one element with a composed label (see
/// `ActivityRowAccessibility`); the inner content's elements are hidden.
final class ActivityCommentRowCell: UITableViewCell {
    static let reuseIdentifier = "ActivityCommentRowCell"

    private let actionHeader = ActivityActionHeaderView()
    /// The reused search comment rendering (body over a context line). Hosted
    /// rather than forked so any future change to comment rendering is shared.
    private let commentContentView = SearchCommentContentView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        actionHeader.translatesAutoresizingMaskIntoConstraints = false
        commentContentView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(actionHeader)
        contentView.addSubview(commentContentView)

        NSLayoutConstraint.activate([
            actionHeader.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            actionHeader.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            actionHeader.trailingAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.trailingAnchor),

            commentContentView.topAnchor.constraint(equalTo: actionHeader.bottomAnchor, constant: 2),
            commentContentView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            commentContentView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            commentContentView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Reset the shared comment rendering so a recycled container starts clean
        // (mirrors `ActivityPostRowCell`).
        commentContentView.prepareForReuse()
        accessibilityLabel = nil
        accessibilityHint = nil
    }

    /// Configures the header, the reused comment rendering (body + an
    /// Activity-specific "<community> · <post title>" context line), and the
    /// composed VoiceOver label. `hint` describes the tap action. `now` is the
    /// reference instant used for the relative-time string — tests inject a
    /// fixed value; production uses `Date()` (the default).
    func configure(item: ActivityItem, comment: ActivityCommentRow, hint: String, now: Date = Date()) {
        actionHeader.configure(act: item.act, occurredAt: item.occurredAt, now: now)

        let context: String
        if comment.parentPostTitle.isEmpty {
            context = comment.communityName
        } else {
            context = "\(comment.communityName) · \(comment.parentPostTitle)"
        }
        commentContentView.configure(content: comment.body, context: context)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = ActivityRowAccessibility.commentLabel(
            act: item.act,
            occurredAt: item.occurredAt,
            comment: comment,
            now: now
        )
        accessibilityHint = hint
        commentContentView.accessibilityElementsHidden = true
        actionHeader.accessibilityElementsHidden = true
    }
}
