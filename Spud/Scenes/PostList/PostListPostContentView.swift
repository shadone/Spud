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

/// The feed post rendering — thumbnail, title, optional link domain / self-text
/// preview, metadata subtitle, and the trailing vote column — wrapped in a
/// `SwipeActionView` so it can host swipe actions. Factored out of
/// `PostListPostCell` as a plain `UIView` so the SAME rendering can be hosted by
/// both the feed cell (`PostListPostCell`) and the Activity timeline's composed
/// post row (`ActivityPostRowCell`).
///
/// Why a `UIView` and not a nested `UITableViewCell`: a `UITableViewCell`'s own
/// `contentView` is attached to the cell by autoresizing mask, which severs the
/// Auto Layout height chain — embedding a whole feed cell inside another cell
/// collapses its content to zero height. A plain content view's intrinsic
/// height propagates through normal Auto Layout to whatever hosts it.
class PostListPostContentView: UIView {
    /// Side length (points) of the square feed thumbnail. Drives both the layout
    /// constraint and the downsample target so the cache holds cell-sized images.
    /// Derived from `ImageService.feedThumbnailPointSize` (the single source of
    /// truth) so the cell, the prefetcher, and the post-detail header's
    /// thumbnail-seed probe all key the same cached entry.
    static let thumbnailDimension: CGFloat = ImageService.feedThumbnailPointSize.width

    // MARK: Public

    var swipeActionConfiguration: SwipeActionView.Configuration? {
        get { swipeActionView.configuration }
        set { swipeActionView.configuration = newValue }
    }

    var swipeActionTriggered: ((SwipeActionView.ActionTrigger) -> Void)?

    /// Invoked when the user taps an image thumbnail, carrying the full-size
    /// image url, optional thumbnail url, and the already-loaded thumbnail
    /// image (for an instant first frame in the viewer).
    var imageTapped: ((_ imageUrl: URL, _ thumbnailUrl: URL?, _ thumbnailImage: UIImage?) -> Void)?

    /// Invoked when the user taps a video post's thumbnail, carrying the
    /// playable video url.
    var videoTapped: ((_ videoUrl: URL) -> Void)?

    /// Invoked when the user taps an external-link post's thumbnail, carrying
    /// the post's external url to open.
    var linkTapped: ((_ linkUrl: URL) -> Void)?

    /// Invoked when the user taps one of the inline vote arrows.
    var voteTapped: ((VoteStatus.Action) -> Void)?

    /// Invoked when the user taps the NSFW blur overlay to reveal the thumbnail.
    var revealNsfwTapped: (() -> Void)?

    // MARK: UI Properties

    lazy var mainHorizontalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.accessibilityIdentifier = "mainHorizontalStackView"

        let subviews = [
            thumbnailContainer,
            contentContainer,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        return stackView
    }()

    lazy var thumbnailContainer: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.accessibilityIdentifier = "thumbnailContainer"
        return stackView
    }()

    lazy var thumbnailView: PostListThumbnailImageView = {
        let view = PostListThumbnailImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    lazy var thumbnailBottomSpacerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.accessibilityIdentifier = "thumbnailBottomSpacerView"
        return view
    }()

    lazy var contentContainer: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.accessibilityIdentifier = "contentVerticalStackView"

        let contentBottomSpacerView: UIView = {
            let view = UIView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.setContentHuggingPriority(.defaultLow, for: .vertical)
            return view
        }()

        // Order matches the Scout cell: title, the optional author line (Search only),
        // then the optional link domain and self-text preview, then the metadata line,
        // then the optional cross-post affordance (last — it's supplementary, not core
        // metadata). The optional rows collapse (and take their spacing with them) when
        // hidden, so the feed — where `authorLabel` stays hidden — is unaffected.
        let subviews = [
            titleLabel,
            authorLabel,
            domainLabel,
            bodyLabel,
            subtitleLabel,
            crossPostLabel,
            contentBottomSpacerView,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        return stackView
    }()

    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.accessibilityIdentifier = "title"
        return label
    }()

    /// The post author's `@user@instance` handle, shown under the title on Search
    /// results only. Hidden (and collapsed out of the stack) on the feed, so feed
    /// cells are unchanged.
    lazy var authorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.isHidden = true
        label.accessibilityIdentifier = "author"
        return label
    }()

    /// The canonical link domain (e.g. "mozilla.org") for external-link posts.
    lazy var domainLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.isHidden = true
        label.accessibilityIdentifier = "domain"
        return label
    }()

    /// A two-line preview of the post's self-text body.
    lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 2
        label.isHidden = true
        label.accessibilityIdentifier = "bodyPreview"
        return label
    }()

    lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        // Wrap rather than truncate when the subtitle is too wide. The view
        // model joins the metadata (score, comments, age, badges) with
        // non-breaking spaces, so the only break opportunity is after the
        // community handle — the subtitle drops the metadata to a second line
        // instead of eliding it.
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.accessibilityIdentifier = "subtitle"
        return label
    }()

    /// "Also in c/name" / "Also in N communities" — shown only when this post is
    /// the primary of one or more collapsed cross-post siblings
    /// (`CrossPostGrouper`, preference-gated, default on). Hidden (and collapsed
    /// out of the stack) otherwise, so an ungrouped post's cell is unchanged. Its
    /// own accessibility element (unlike `authorLabel`) since it carries
    /// information the title's spoken label doesn't include.
    lazy var crossPostLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.isHidden = true
        label.accessibilityIdentifier = "crossPostAffordance"
        return label
    }()

    /// Trailing column of persistent up/down vote arrows (the Scout signature),
    /// kept as a centered pair via equal-height flexible spacers so they never
    /// spread apart on tall multi-line cells.
    lazy var voteColumn: UIStackView = {
        let topSpacer = UIView()
        let bottomSpacer = UIView()
        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        bottomSpacer.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView(arrangedSubviews: [topSpacer, upvoteButton, downvoteButton, bottomSpacer])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 2
        stackView.accessibilityIdentifier = "voteColumn"

        NSLayoutConstraint.activate([
            topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor),
        ])
        return stackView
    }()

    lazy var upvoteButton: UIButton = makeVoteButton(
        symbolName: "arrow.up",
        accessibilityLabel: NSLocalizedString("Upvote", comment: "VoiceOver label for the upvote arrow in a post cell"),
        action: #selector(upvoteButtonTapped)
    )

    lazy var downvoteButton: UIButton = makeVoteButton(
        symbolName: "arrow.down",
        accessibilityLabel: NSLocalizedString("Downvote", comment: "VoiceOver label for the downvote arrow in a post cell"),
        action: #selector(downvoteButtonTapped)
    )

    lazy var swipeActionView: SwipeActionView = {
        let view = SwipeActionView(
            contentView: mainHorizontalStackView,
            margin: UIEdgeInsets(top: 16, left: 16, bottom: -16, right: -16),
            configuration: nil
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        view.trigger = { [weak self] action in
            self?.swipeActionTriggered?(action)
        }
        return view
    }()

    /// Dog-ear fold shown at the trailing corner when arrows are hidden and the
    /// post is voted. Sits above `swipeActionView` as a non-interactive overlay.
    private lazy var voteFold: VoteFoldView = {
        let view = VoteFoldView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    // MARK: Private

    private var thumbnailLoadTask: Task<Void, Never>?

    /// Full-size image url + last-loaded thumbnail image for the tap-to-open
    /// gesture. Set during `configure`; reset in `prepareForReuse`.
    private var tappableImageUrl: URL?
    private var tappableThumbnailUrl: URL?
    private var tappableVideoUrl: URL?
    private var tappableLinkUrl: URL?
    private var loadedThumbnailImage: UIImage?

    /// The thumbnail position applied to the current layout, so `configure`
    /// only relays the stack when it actually changes (cheaper on reuse).
    private var appliedThumbnailPosition: ThumbnailPosition?
    /// Whether the vote column is in the current layout, same rationale.
    private var appliedShowVoteButtons: Bool?
    /// The density applied to the current layout, same rationale.
    private var appliedDensity: PostDensity?
    /// Resolved active colors cached from `configure` so `applyVoteState` has
    /// them without needing the view model. Default to `.tertiaryLabel` (the
    /// neutral-state tint) so the initial state before the first configure is
    /// visually correct.
    private var appliedUpvoteColor: UIColor = .tertiaryLabel
    private var appliedDownvoteColor: UIColor = .tertiaryLabel
    /// The thumbnail image URL currently shown or loading. `reconfigureItems`
    /// re-runs `configure` on the live on-screen cell, so this lets the image
    /// load short-circuit when the post's thumbnail is unchanged — otherwise the
    /// already-shown image gets torn down and re-fetched on every snapshot apply,
    /// which read as the thumbnail "zooming in". Reset on reuse.
    private var appliedThumbnailUrl: URL?
    /// The vote status applied during the most recent `configure` call, or `nil`
    /// when the cell has been freshly reused (reset in `prepareForReuse`). Used
    /// to distinguish an in-place optimistic vote reconfigure (which must animate)
    /// from a fresh bind after cell reuse (which must not).
    private var appliedVoteStatus: VoteStatus?

    /// Vertical-anchor constraints that position the 28×28 fold at the top or
    /// bottom trailing corner. Exactly one is active at a time (the other is
    /// deactivated), toggled in `applyVoteState` based on status.
    private lazy var voteFoldTop = voteFold.topAnchor.constraint(equalTo: topAnchor)
    private lazy var voteFoldBottom = voteFold.bottomAnchor.constraint(equalTo: bottomAnchor)

    // MARK: Functions

    init() {
        super.init(frame: .zero)

        addSubview(swipeActionView)
        // The fold sits above the swipe layer as a non-interactive overlay. It
        // is pinned to the cell's trailing edge (flush to the visible right edge
        // of the content area) and anchored vertically via `voteFoldTop` /
        // `voteFoldBottom` (toggled in `applyVoteState`).
        addSubview(voteFold)

        let subviews = [
            thumbnailView,
            thumbnailBottomSpacerView,
        ]
        for view in subviews {
            thumbnailContainer.addArrangedSubview(view)
        }

        NSLayoutConstraint.activate([
            swipeActionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            swipeActionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            swipeActionView.topAnchor.constraint(equalTo: topAnchor),
            swipeActionView.bottomAnchor.constraint(equalTo: bottomAnchor),

            thumbnailView.widthAnchor.constraint(equalToConstant: Self.thumbnailDimension),
            thumbnailView.heightAnchor.constraint(equalToConstant: Self.thumbnailDimension),

            voteColumn.widthAnchor.constraint(equalToConstant: 34),

            voteFold.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        thumbnailView.isUserInteractionEnabled = true
        let imageTap = UITapGestureRecognizer(target: self, action: #selector(thumbnailTapped))
        thumbnailView.addGestureRecognizer(imageTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Resets the rendering for reuse: cancels the thumbnail load and clears the
    /// callbacks and per-row tappable state. Called from the host cell's
    /// `prepareForReuse`.
    func prepareForReuse() {
        thumbnailLoadTask?.cancel()
        thumbnailLoadTask = nil
        appliedThumbnailUrl = nil
        thumbnailView.prepareForReuse()

        tappableImageUrl = nil
        tappableThumbnailUrl = nil
        tappableVideoUrl = nil
        tappableLinkUrl = nil
        loadedThumbnailImage = nil

        // Leave `appliedThumbnailPosition` / `appliedDensity` intact: they
        // describe the current layout, and `configure` only relays when they
        // change. Resetting them here would force a needless relayout on every
        // reuse.
        //
        // `appliedVoteStatus` IS reset: nil signals that the next `configure` is
        // a fresh bind (no animation), not an in-place optimistic vote reconfigure
        // (which should animate). `prepareForReuse` runs on cell reuse but NOT on
        // the `reconfigureItems` path — that's the key distinction.
        appliedVoteStatus = nil

        swipeActionConfiguration = nil
        swipeActionTriggered = nil
        imageTapped = nil
        videoTapped = nil
        linkTapped = nil
        voteTapped = nil
        revealNsfwTapped = nil

        authorLabel.attributedText = nil
        authorLabel.isHidden = true
        domainLabel.attributedText = nil
        domainLabel.isHidden = true
        bodyLabel.attributedText = nil
        bodyLabel.isHidden = true

        crossPostLabel.attributedText = nil
        crossPostLabel.isHidden = true
        crossPostLabel.isAccessibilityElement = false
    }

    @objc
    private func thumbnailTapped() {
        if let tappableVideoUrl {
            videoTapped?(tappableVideoUrl)
        } else if let tappableLinkUrl {
            linkTapped?(tappableLinkUrl)
        } else if let tappableImageUrl {
            imageTapped?(tappableImageUrl, tappableThumbnailUrl, loadedThumbnailImage)
        }
    }

    @objc
    private func upvoteButtonTapped() {
        voteTapped?(.upvote)
    }

    @objc
    private func downvoteButtonTapped() {
        voteTapped?(.downvote)
    }

    /// Builds one inline vote arrow. `UIButton(type: .system)` tints the template
    /// symbol with `tintColor`, which `configure` swaps per vote state.
    private func makeVoteButton(
        symbolName: String,
        accessibilityLabel: String,
        action: Selector
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(
            UIImage(
                systemName: symbolName,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            ),
            for: .normal
        )
        button.tintColor = .tertiaryLabel
        button.layer.cornerRadius = VoteFillStyle.capsuleCornerRadius
        button.clipsToBounds = true
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 28),
        ])
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    /// Renders the active arrow as a filled capsule (white glyph on the vote
    /// token) and the other as a tertiary hairline. When vote arrows are hidden
    /// (`appliedShowVoteButtons == false`), shows the dog-ear fold instead.
    /// The pill and the fold are mutually exclusive.
    ///
    /// Must be called after `applyLayout` in `configure` so that
    /// `appliedShowVoteButtons` is already set.
    private func applyVoteState(_ status: VoteStatus, animated: Bool) {
        // Pill (arrows shown) and fold (arrows hidden) are mutually exclusive.
        let showFold = appliedShowVoteButtons == false && status != .neutral
        style(upvoteButton, filled: status == .up, fill: appliedUpvoteColor)
        style(downvoteButton, filled: status == .down, fill: appliedDownvoteColor)

        // Keep a valid vertical anchor in every state (the fold is hidden for
        // neutral, but leaving both inactive makes AutoLayout complain). Top by
        // default; a downvote moves it to the bottom corner.
        voteFoldTop.isActive = status != .down
        voteFoldBottom.isActive = status == .down
        voteFold.configure(
            status: showFold ? status : .neutral,
            upColor: appliedUpvoteColor,
            downColor: appliedDownvoteColor
        )

        if animated {
            if !showFold, status == .up { VoteFillStyle.animateCommit(upvoteButton) }
            if !showFold, status == .down { VoteFillStyle.animateCommit(downvoteButton) }
            if showFold { VoteFillStyle.animateCommit(voteFold) }
        }
    }

    private func style(_ button: UIButton, filled: Bool, fill: UIColor) {
        button.backgroundColor = filled ? fill : .clear
        button.tintColor = filled ? VoteFillStyle.filledGlyphColor : .tertiaryLabel
        button.accessibilityTraits = filled ? [.button, .selected] : [.button]
    }

    /// Applies the post-density cell metrics: outer content margin, the gap
    /// between thumbnail and text, and the title/subtitle spacing.
    private func applyDensity(_ density: PostDensity) {
        guard density != appliedDensity else { return }
        appliedDensity = density

        let margin = density.cellMargin
        swipeActionView.setContentMargin(
            UIEdgeInsets(top: margin, left: margin, bottom: -margin, right: -margin)
        )
        mainHorizontalStackView.spacing = density.horizontalSpacing
        // Uniform spacing between the (collapsible) content rows. Half the
        // title/subtitle metric reads right with the extra domain/body rows.
        contentContainer.spacing = density.titleSubtitleSpacing / 2 + 1
    }

    /// Relays the thumbnail to the requested side (or removes it when hidden)
    /// and adds or drops the trailing vote column. Rebuilds the horizontal
    /// stack only when the resolved layout actually changes (cheaper on reuse).
    private func applyLayout(position: ThumbnailPosition, showVoteButtons: Bool) {
        guard position != appliedThumbnailPosition || showVoteButtons != appliedShowVoteButtons else { return }
        appliedThumbnailPosition = position
        appliedShowVoteButtons = showVoteButtons

        // Rebuild the horizontal stack's arranged subviews in the right order.
        for view in mainHorizontalStackView.arrangedSubviews {
            mainHorizontalStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        switch position {
        case .left:
            thumbnailContainer.isHidden = false
            mainHorizontalStackView.addArrangedSubview(thumbnailContainer)
            mainHorizontalStackView.addArrangedSubview(contentContainer)
        case .right:
            thumbnailContainer.isHidden = false
            mainHorizontalStackView.addArrangedSubview(contentContainer)
            mainHorizontalStackView.addArrangedSubview(thumbnailContainer)
        case .hidden:
            thumbnailContainer.isHidden = true
            mainHorizontalStackView.addArrangedSubview(contentContainer)
        }

        // The vote column always trails the content, regardless of thumbnail
        // side. Dropped entirely (not just hidden) when the user turns it off.
        if showVoteButtons {
            mainHorizontalStackView.addArrangedSubview(voteColumn)
        }
    }

    func configure(with viewModel: PostListPostViewModel, imageService: ImageServiceType) {
        titleLabel.attributedText = viewModel.title
        subtitleLabel.attributedText = viewModel.subtitle

        // VoiceOver reads the cell as a coherent statement. The cell stays a
        // container (so the title/subtitle static texts remain queryable by
        // XCUITest and by VoiceOver users navigating element-by-element), but
        // we override the subtitle's spoken text — the visible subtitle is an
        // icon-and-value run that VoiceOver would otherwise read as glyphs — and
        // give the title element the full cell summary plus a tap hint.
        titleLabel.accessibilityLabel = viewModel.accessibilityLabel
        titleLabel.accessibilityHint = viewModel.accessibilityHint
        titleLabel.accessibilityTraits = [.staticText, .button]

        subtitleLabel.accessibilityLabel = viewModel.subtitleAccessibilityLabel

        // The author line (Search only) is folded into the title's spoken label, so
        // hide the visible label from VoiceOver to avoid announcing the handle twice.
        authorLabel.attributedText = viewModel.authorLine
        authorLabel.isHidden = viewModel.authorLine == nil
        authorLabel.isAccessibilityElement = false

        domainLabel.attributedText = viewModel.domainText
        domainLabel.isHidden = viewModel.domainText == nil

        bodyLabel.attributedText = viewModel.bodyPreview
        bodyLabel.isHidden = viewModel.bodyPreview == nil

        // The visible text carries an inline SF Symbol attachment, which
        // VoiceOver can't pronounce — override with the plain-text label, same
        // treatment as `subtitleLabel` above.
        crossPostLabel.attributedText = viewModel.crossPostAffordanceText
        crossPostLabel.isHidden = viewModel.crossPostAffordanceText == nil
        crossPostLabel.isAccessibilityElement = viewModel.crossPostAffordanceText != nil
        crossPostLabel.accessibilityLabel = viewModel.crossPostAffordanceAccessibilityLabel
        crossPostLabel.accessibilityTraits = .staticText

        appliedUpvoteColor = viewModel.upvoteActiveColor
        appliedDownvoteColor = viewModel.downvoteActiveColor

        applyDensity(viewModel.density)
        // applyLayout must run first: it sets `appliedShowVoteButtons`, which
        // `applyVoteState` reads to decide whether to show the pill or the fold.
        applyLayout(position: viewModel.thumbnailPosition, showVoteButtons: viewModel.showVoteButtons)
        // Animate only when THIS same cell's vote flips to a voted state in place
        // (an optimistic vote reconfigures the cell without prepareForReuse); a
        // fresh bind after reuse (appliedVoteStatus == nil) or a scroll must not spring.
        let animateVote = appliedVoteStatus != nil
            && appliedVoteStatus != viewModel.voteStatus
            && viewModel.voteStatus != .neutral
        applyVoteState(viewModel.voteStatus, animated: animateVote)
        appliedVoteStatus = viewModel.voteStatus

        // A hidden thumbnail needs no image work.
        guard viewModel.thumbnailPosition.showsThumbnail else {
            thumbnailLoadTask?.cancel()
            thumbnailLoadTask = nil
            appliedThumbnailUrl = nil
            tappableImageUrl = nil
            tappableThumbnailUrl = nil
            return
        }

        thumbnailView.badgeText = nil
        thumbnailView.badgeSymbolName = nil
        thumbnailView.showsPlayIcon = false
        tappableVideoUrl = nil
        tappableLinkUrl = nil
        switch viewModel.thumbnail {
        case .text:
            tappableImageUrl = nil
            tappableThumbnailUrl = nil
            setStaticThumbnail(.text)
            thumbnailView.isAccessibilityElement = false
            // Decorative placeholder; let the tap fall through to the cell so
            // tapping anywhere opens the post.
            thumbnailView.isUserInteractionEnabled = false

        case let .image(thumbnailUrl):
            tappableImageUrl = viewModel.fullImageUrl
            tappableThumbnailUrl = thumbnailUrl
            // The inline thumbnail shows a static frame; badge animated posts
            // so they read as playable in the feed.
            thumbnailView.badgeText = viewModel.fullImageUrl?.isAnimatedImage == true ? "GIF" : nil
            // A tappable image preview: expose it as an image element that
            // opens the full-size viewer.
            thumbnailView.isUserInteractionEnabled = true
            thumbnailView.isAccessibilityElement = true
            thumbnailView.accessibilityLabel = NSLocalizedString(
                "Post image",
                comment: "VoiceOver label for a post's thumbnail image"
            )
            thumbnailView.accessibilityHint = NSLocalizedString(
                "Opens the full-size image",
                comment: "VoiceOver hint for a post thumbnail"
            )
            thumbnailView.accessibilityTraits = [.image, .button]
            loadThumbnail(thumbnailUrl, imageService: imageService)

        case let .linkImage(thumbnailUrl, linkUrl):
            tappableImageUrl = nil
            tappableThumbnailUrl = nil
            tappableLinkUrl = linkUrl
            // The embed image previews the link; a globe badge marks it as an
            // external link, and tapping opens that link.
            thumbnailView.badgeSymbolName = "globe"
            applyLinkAccessibility()
            loadThumbnail(thumbnailUrl, imageService: imageService)

        case let .link(linkUrl):
            tappableImageUrl = nil
            tappableThumbnailUrl = nil
            tappableLinkUrl = linkUrl
            // No embed image: the globe placeholder marks it as an external
            // link, and tapping opens that link.
            setStaticThumbnail(.link)
            applyLinkAccessibility()

        case let .video(posterUrl, videoUrl):
            tappableImageUrl = nil
            tappableThumbnailUrl = nil
            tappableVideoUrl = videoUrl
            thumbnailView.showsPlayIcon = true
            thumbnailView.isUserInteractionEnabled = true
            thumbnailView.isAccessibilityElement = true
            thumbnailView.accessibilityLabel = NSLocalizedString(
                "Video",
                comment: "VoiceOver label for a post's video thumbnail"
            )
            thumbnailView.accessibilityHint = NSLocalizedString(
                "Plays the video",
                comment: "VoiceOver hint for a post video thumbnail"
            )
            thumbnailView.accessibilityTraits = [.image, .button]
            if let posterUrl {
                loadThumbnail(posterUrl, imageService: imageService)
            } else {
                // No poster: show the placeholder behind the play indicator.
                setStaticThumbnail(.text)
            }
        }

        thumbnailView.isBlurred = viewModel.isThumbnailBlurred
        thumbnailView.onRevealBlur = { [weak self] in self?.revealNsfwTapped?() }
    }

    /// Exposes the thumbnail as a tappable link element (used by both the
    /// embed-image and image-less external-link cases): tapping opens the link.
    private func applyLinkAccessibility() {
        thumbnailView.isUserInteractionEnabled = true
        thumbnailView.isAccessibilityElement = true
        thumbnailView.accessibilityLabel = NSLocalizedString(
            "External link",
            comment: "VoiceOver label for a post's external-link thumbnail"
        )
        thumbnailView.accessibilityHint = NSLocalizedString(
            "Opens the link",
            comment: "VoiceOver hint for a post's external-link thumbnail"
        )
        thumbnailView.accessibilityTraits = [.link, .button]
    }

    /// Shows a non-image placeholder (text, link, or broken), cancelling any
    /// in-flight thumbnail load and clearing the load memo so a later image
    /// re-fetches.
    private func setStaticThumbnail(_ type: PostListThumbnailImageView.ThumbnailType) {
        thumbnailLoadTask?.cancel()
        thumbnailLoadTask = nil
        appliedThumbnailUrl = nil
        thumbnailView.thumbnailType = type
    }

    /// Loads a thumbnail image into `thumbnailView`, showing the broken-image
    /// state on failure. Shared by image and link-preview posts.
    ///
    /// Idempotent across `configure` calls: `reconfigureItems` re-runs the cell
    /// provider on the *live* on-screen cell, so re-clearing the already-shown
    /// image and re-issuing the fetch would tear the thumbnail down and rebuild
    /// it on every snapshot apply (pagination, vote, read-state). Inside the
    /// diffable apply's animation that read as the thumbnail "zooming in". When
    /// the URL is unchanged we leave the existing image (or in-flight load) be.
    private func loadThumbnail(_ thumbnailUrl: URL, imageService: ImageServiceType) {
        guard thumbnailUrl != appliedThumbnailUrl else { return }
        appliedThumbnailUrl = thumbnailUrl

        thumbnailLoadTask?.cancel()
        // Clear only when starting a genuinely new image, so the previous post's
        // thumbnail doesn't linger under the incoming content.
        thumbnailView.thumbnailType = .none

        let size = ImageService.feedThumbnailPointSize
        thumbnailLoadTask = Task { [weak self] in
            for await state in imageService.fetch(thumbnailUrl, downsampleTo: size) {
                if Task.isCancelled { return }
                guard let self else { return }
                switch state {
                case .loading:
                    thumbnailView.thumbnailType = .none
                case .failure:
                    thumbnailView.thumbnailType = .imageFailure
                case let .ready(image):
                    loadedThumbnailImage = image
                    thumbnailView.thumbnailType = .image(image)
                }
            }
        }
    }
}
