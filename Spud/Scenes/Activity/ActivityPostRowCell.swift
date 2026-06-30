//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// An activity timeline row for a post: the `ActivityActionHeaderView` verb chip
/// ("You upvoted · 2h") above a fully-featured `PostListPostCell` render, so the
/// row shows the same thumbnail, body preview, vote arrows, NSFW blur, and
/// status badges as the feed (rather than a hand-rolled label stack). The inner
/// feed cell is reused, not forked - the view controller configures it through
/// the exposed `postCell` exactly as the feed and Person screens do.
///
/// VoiceOver treats the whole row as a single element with a composed label (see
/// `ActivityRowAccessibility`); the inner cell's own elements are hidden so the
/// score/▲▼ glyphs are not read as "black up-pointing triangle".
final class ActivityPostRowCell: UITableViewCell {
    static let reuseIdentifier = "ActivityPostRowCell"

    /// The reused feed cell. Exposed so the view controller can configure its
    /// view model, callbacks (vote / media / reveal), and swipe actions directly,
    /// mirroring `PersonViewController.makePostCell`.
    let postCell = PostListPostCell(style: .default, reuseIdentifier: nil)

    private let actionHeader = ActivityActionHeaderView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        actionHeader.translatesAutoresizingMaskIntoConstraints = false
        postCell.translatesAutoresizingMaskIntoConstraints = false
        postCell.contentView.backgroundColor = .clear

        contentView.addSubview(actionHeader)
        contentView.addSubview(postCell)

        NSLayoutConstraint.activate([
            // The header is indented to line up with the feed cell's content,
            // which sits 16pt inside its leading edge (SwipeActionView margin).
            actionHeader.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            actionHeader.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            actionHeader.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),

            postCell.topAnchor.constraint(equalTo: actionHeader.bottomAnchor),
            postCell.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            postCell.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            postCell.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Reset the inner feed cell (cancels its thumbnail load and clears its
        // callbacks) so a recycled container starts clean.
        postCell.prepareForReuse()
        accessibilityLabel = nil
        accessibilityHint = nil
    }

    /// Configures the action header and the composed VoiceOver label. The inner
    /// `postCell` is configured separately by the view controller (view model +
    /// callbacks). `postSummary` is the reused `PostListPostViewModel`
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
        // The row is one element; keep VoiceOver out of the inner cell's
        // thumbnail / vote-arrow / score sub-elements.
        postCell.accessibilityElementsHidden = true
        actionHeader.accessibilityElementsHidden = true
    }
}
