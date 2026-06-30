//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

/// The feed's post cell. A thin `UITableViewCell` wrapper that hosts the shared
/// `PostListPostContentView` (the actual thumbnail / title / body / vote-arrow
/// rendering), pinned to the cell's `contentView`. The same content view is
/// reused — not forked — by the Activity timeline's composed post row, so the
/// feed and Activity render identically. The cell forwards the content view's
/// configuration and callbacks so existing feed / Person call sites are
/// unchanged.
class PostListPostCell: UITableViewCell {
    static let reuseIdentifier = "PostListPostCell"

    /// Side length (points) of the square feed thumbnail. Re-exported from the
    /// content view so existing references resolve against the cell too.
    static let thumbnailDimension = PostListPostContentView.thumbnailDimension

    // MARK: Public

    /// Server post id of the row this cell currently shows, used by the feed's
    /// seen-on-screen capture in didEndDisplaying. Not part of rendering.
    var seenTrackingServerPostId: Int64?

    /// The shared post rendering. Hosted here and (separately) by the Activity
    /// post row; exposed so the feed can drive it via the forwarding members
    /// below.
    let postContentView = PostListPostContentView()

    var swipeActionConfiguration: SwipeActionView.Configuration? {
        get { postContentView.swipeActionConfiguration }
        set { postContentView.swipeActionConfiguration = newValue }
    }

    var swipeActionTriggered: ((SwipeActionView.ActionTrigger) -> Void)? {
        get { postContentView.swipeActionTriggered }
        set { postContentView.swipeActionTriggered = newValue }
    }

    /// Invoked when the user taps an image thumbnail (full-size url, optional
    /// thumbnail url, already-loaded thumbnail image).
    var imageTapped: ((_ imageUrl: URL, _ thumbnailUrl: URL?, _ thumbnailImage: UIImage?) -> Void)? {
        get { postContentView.imageTapped }
        set { postContentView.imageTapped = newValue }
    }

    /// Invoked when the user taps a video post's thumbnail.
    var videoTapped: ((_ videoUrl: URL) -> Void)? {
        get { postContentView.videoTapped }
        set { postContentView.videoTapped = newValue }
    }

    /// Invoked when the user taps an external-link post's thumbnail.
    var linkTapped: ((_ linkUrl: URL) -> Void)? {
        get { postContentView.linkTapped }
        set { postContentView.linkTapped = newValue }
    }

    /// Invoked when the user taps one of the inline vote arrows.
    var voteTapped: ((VoteStatus.Action) -> Void)? {
        get { postContentView.voteTapped }
        set { postContentView.voteTapped = newValue }
    }

    /// Invoked when the user taps the NSFW blur overlay to reveal the thumbnail.
    var revealNsfwTapped: (() -> Void)? {
        get { postContentView.revealNsfwTapped }
        set { postContentView.revealNsfwTapped = newValue }
    }

    // MARK: Functions

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        postContentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(postContentView)

        NSLayoutConstraint.activate([
            postContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            postContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            postContentView.topAnchor.constraint(equalTo: contentView.topAnchor),
            postContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        seenTrackingServerPostId = nil
        postContentView.prepareForReuse()
    }

    /// Configures the hosted rendering from a post view model. Mirrors the prior
    /// cell-level API so feed / Person call sites are unchanged.
    func configure(with viewModel: PostListPostViewModel, imageService: ImageServiceType) {
        postContentView.configure(with: viewModel, imageService: imageService)
    }
}
