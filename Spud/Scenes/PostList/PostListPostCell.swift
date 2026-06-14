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

class PostListPostCell: UITableViewCell {
    static let reuseIdentifier = "PostListPostCell"

    /// Side length (points) of the square feed thumbnail. Drives both the layout
    /// constraint and the downsample target so the cache holds cell-sized images.
    static let thumbnailDimension: CGFloat = 64

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

    /// Invoked when the user taps one of the inline vote arrows.
    var voteTapped: ((VoteStatus.Action) -> Void)?

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

        // Order matches the Scout cell: title, then the optional link domain and
        // self-text preview, then the metadata line. The optional rows collapse
        // (and take their spacing with them) when hidden.
        let subviews = [
            titleLabel,
            domainLabel,
            bodyLabel,
            subtitleLabel,
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
        label.accessibilityIdentifier = "subtitle"
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

    // MARK: Private

    private var thumbnailLoadTask: Task<Void, Never>?

    /// Full-size image url + last-loaded thumbnail image for the tap-to-open
    /// gesture. Set during `configure`; reset in `prepareForReuse`.
    private var tappableImageUrl: URL?
    private var tappableThumbnailUrl: URL?
    private var tappableVideoUrl: URL?
    private var loadedThumbnailImage: UIImage?

    /// The thumbnail position applied to the current layout, so `configure`
    /// only relays the stack when it actually changes (cheaper on reuse).
    private var appliedThumbnailPosition: ThumbnailPosition?
    /// Whether the vote column is in the current layout, same rationale.
    private var appliedShowVoteButtons: Bool?
    /// The density applied to the current layout, same rationale.
    private var appliedDensity: PostDensity?
    /// The thumbnail image URL currently shown or loading. `reconfigureItems`
    /// re-runs `configure` on the live on-screen cell, so this lets the image
    /// load short-circuit when the post's thumbnail is unchanged — otherwise the
    /// already-shown image gets torn down and re-fetched on every snapshot apply,
    /// which read as the thumbnail "zooming in". Reset on reuse.
    private var appliedThumbnailUrl: URL?

    // MARK: Functions

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        contentView.addSubview(swipeActionView)

        let subviews = [
            thumbnailView,
            thumbnailBottomSpacerView,
        ]
        for view in subviews {
            thumbnailContainer.addArrangedSubview(view)
        }

        NSLayoutConstraint.activate([
            swipeActionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            swipeActionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            swipeActionView.topAnchor.constraint(equalTo: contentView.topAnchor),
            swipeActionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            thumbnailView.widthAnchor.constraint(equalToConstant: Self.thumbnailDimension),
            thumbnailView.heightAnchor.constraint(equalToConstant: Self.thumbnailDimension),

            voteColumn.widthAnchor.constraint(equalToConstant: 34),
        ])

        thumbnailView.isUserInteractionEnabled = true
        let imageTap = UITapGestureRecognizer(target: self, action: #selector(thumbnailTapped))
        thumbnailView.addGestureRecognizer(imageTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        thumbnailLoadTask?.cancel()
        thumbnailLoadTask = nil
        appliedThumbnailUrl = nil
        thumbnailView.prepareForReuse()

        tappableImageUrl = nil
        tappableThumbnailUrl = nil
        tappableVideoUrl = nil
        loadedThumbnailImage = nil

        // Leave `appliedThumbnailPosition` / `appliedDensity` intact: they
        // describe the current layout, and `configure` only relays when they
        // change. Resetting them here would force a needless relayout on every
        // reuse.

        swipeActionConfiguration = nil
        swipeActionTriggered = nil
        imageTapped = nil
        videoTapped = nil
        voteTapped = nil

        domainLabel.attributedText = nil
        domainLabel.isHidden = true
        bodyLabel.attributedText = nil
        bodyLabel.isHidden = true
    }

    @objc
    private func thumbnailTapped() {
        if let tappableVideoUrl {
            videoTapped?(tappableVideoUrl)
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
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
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

        domainLabel.attributedText = viewModel.domainText
        domainLabel.isHidden = viewModel.domainText == nil

        bodyLabel.attributedText = viewModel.bodyPreview
        bodyLabel.isHidden = viewModel.bodyPreview == nil

        upvoteButton.tintColor = viewModel.voteStatus == .up ? viewModel.upvoteActiveColor : .tertiaryLabel
        downvoteButton.tintColor = viewModel.voteStatus == .down ? viewModel.downvoteActiveColor : .tertiaryLabel

        applyDensity(viewModel.density)
        applyLayout(position: viewModel.thumbnailPosition, showVoteButtons: viewModel.showVoteButtons)

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
        thumbnailView.showsPlayIcon = false
        tappableVideoUrl = nil
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

        case let .linkImage(thumbnailUrl):
            tappableImageUrl = nil
            tappableThumbnailUrl = nil
            // The embed image previews the link; tapping it falls through to the
            // cell (opens the post), like the detail view's link preview.
            thumbnailView.isUserInteractionEnabled = false
            thumbnailView.isAccessibilityElement = false
            loadThumbnail(thumbnailUrl, imageService: imageService)

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
    }

    /// Shows a non-image placeholder (text or broken), cancelling any in-flight
    /// thumbnail load and clearing the load memo so a later image re-fetches.
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

        let size = CGSize(width: Self.thumbnailDimension, height: Self.thumbnailDimension)
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
