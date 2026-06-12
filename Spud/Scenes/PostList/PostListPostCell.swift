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

        let subviews = [
            titleLabel,
            subtitleLabel,
            contentBottomSpacerView,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        stackView.setCustomSpacing(8, after: titleLabel)

        return stackView
    }()

    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.accessibilityIdentifier = "title"
        return label
    }()

    lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "subtitle"
        return label
    }()

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
    private var loadedThumbnailImage: UIImage?

    /// The thumbnail position applied to the current layout, so `configure`
    /// only relays the stack when it actually changes (cheaper on reuse).
    private var appliedThumbnailPosition: ThumbnailPosition?
    /// The density applied to the current layout, same rationale.
    private var appliedDensity: PostDensity?

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

            thumbnailView.widthAnchor.constraint(equalToConstant: 64),
            thumbnailView.heightAnchor.constraint(equalToConstant: 64),
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
        thumbnailView.prepareForReuse()

        tappableImageUrl = nil
        tappableThumbnailUrl = nil
        loadedThumbnailImage = nil

        // Leave `appliedThumbnailPosition` / `appliedDensity` intact: they
        // describe the current layout, and `configure` only relays when they
        // change. Resetting them here would force a needless relayout on every
        // reuse.

        swipeActionConfiguration = nil
        swipeActionTriggered = nil
        imageTapped = nil
    }

    @objc
    private func thumbnailTapped() {
        guard let tappableImageUrl else { return }
        imageTapped?(tappableImageUrl, tappableThumbnailUrl, loadedThumbnailImage)
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
        contentContainer.setCustomSpacing(density.titleSubtitleSpacing, after: titleLabel)
    }

    /// Relays the thumbnail to the requested side, or removes it when hidden.
    private func applyThumbnailPosition(_ position: ThumbnailPosition) {
        guard position != appliedThumbnailPosition else { return }
        appliedThumbnailPosition = position

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

        applyDensity(viewModel.density)
        applyThumbnailPosition(viewModel.thumbnailPosition)

        // A hidden thumbnail needs no image work.
        guard viewModel.thumbnailPosition.showsThumbnail else {
            thumbnailLoadTask?.cancel()
            thumbnailLoadTask = nil
            tappableImageUrl = nil
            tappableThumbnailUrl = nil
            return
        }

        thumbnailLoadTask?.cancel()
        tappableImageUrl = viewModel.fullImageUrl
        switch viewModel.thumbnail {
        case .text:
            thumbnailView.thumbnailType = .text
            thumbnailView.isAccessibilityElement = false
            tappableThumbnailUrl = nil
        case let .image(thumbnailUrl):
            thumbnailView.thumbnailType = .none
            // The inline thumbnail shows a static frame; badge animated posts
            // so they read as playable in the feed.
            thumbnailView.badgeText = viewModel.fullImageUrl?.isAnimatedImage == true ? "GIF" : nil
            // A tappable image preview: expose it as an image element that
            // opens the full-size viewer.
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
            tappableThumbnailUrl = thumbnailUrl
            thumbnailLoadTask = Task { [weak self] in
                for await state in imageService.fetch(thumbnailUrl) {
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
}
