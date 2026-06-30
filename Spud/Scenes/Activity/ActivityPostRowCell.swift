//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// An activity timeline row for a post: the `ActivityActionHeaderView` verb chip
/// ("You upvoted · 2h") above a fully-featured `PostListPostContentView` render,
/// so the row shows the same thumbnail, body preview, vote arrows, NSFW blur, and
/// status badges as the feed (rather than a hand-rolled label stack).
///
/// The post rendering is the SHARED `PostListPostContentView` — the exact view
/// the feed cell hosts — configured by the view controller through the exposed
/// `postContentView` the same way the feed and Person screens do. Critically it
/// is a plain content `UIView`, not a nested `UITableViewCell`: a nested cell's
/// own `contentView` is attached by autoresizing mask, which severs the Auto
/// Layout height chain and collapses the embedded content to ~0pt. Hosting the
/// content view directly lets its intrinsic height drive the row.
///
/// VoiceOver treats the whole row as a single element with a composed label (see
/// `ActivityRowAccessibility`); the inner content's own elements are hidden so the
/// score/▲▼ glyphs are not read as "black up-pointing triangle".
final class ActivityPostRowCell: UITableViewCell {
    static let reuseIdentifier = "ActivityPostRowCell"

    /// The reused feed post rendering. Exposed so the view controller can
    /// configure its view model and callbacks (vote / media / reveal) directly,
    /// mirroring `PersonViewController.makePostCell`.
    let postContentView = PostListPostContentView()

    private let actionHeader = ActivityActionHeaderView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        actionHeader.translatesAutoresizingMaskIntoConstraints = false
        postContentView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(actionHeader)
        contentView.addSubview(postContentView)

        NSLayoutConstraint.activate([
            // The header is indented to line up with the feed content, which sits
            // 16pt inside its leading edge (the content view's own margin).
            actionHeader.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            actionHeader.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            actionHeader.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),

            postContentView.topAnchor.constraint(equalTo: actionHeader.bottomAnchor),
            postContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            postContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            postContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Reset the shared rendering (cancels its thumbnail load and clears its
        // callbacks) so a recycled container starts clean.
        postContentView.prepareForReuse()
        accessibilityLabel = nil
        accessibilityHint = nil
    }

    /// Configures the action header and the composed VoiceOver label. The inner
    /// `postContentView` is configured separately by the view controller (view
    /// model + callbacks). `postSummary` is the reused `PostListPostViewModel`
    /// accessibility label; `hint` describes the tap action.
    func configure(item: ActivityItem, postSummary: String, hint: String) {
        actionHeader.configure(act: item.act, occurredAt: item.occurredAt)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = ActivityRowAccessibility.postLabel(
            act: item.act,
            occurredAt: item.occurredAt,
            postSummary: postSummary
        )
        accessibilityHint = hint
        // The row is one element; keep VoiceOver out of the inner content's
        // thumbnail / vote-arrow / score sub-elements.
        postContentView.accessibilityElementsHidden = true
        actionHeader.accessibilityElementsHidden = true
    }
}
