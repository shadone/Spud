//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import OSLog
import SafariServices
import SpudDataKit
import SpudMarkdownKit
import SpudUIKit
import SpudUtilKit
import UIKit

private let logger = Logger.app

class PostDetailHeaderCell: UITableViewCellBase {
    static let reuseIdentifier = "PostDetailHeaderCell"

    // MARK: Public

    var linkTapped: ((URL) -> Void)?
    var linkLongPressed: ((URL) -> Void)?
    var linkTappedFromPreview: ((SFSafariViewController) -> Void)?
    var appService: AppServiceType?

    /// Invoked when the user taps the post's main image, carrying the
    /// full-size image url, optional thumbnail url, and whatever image is
    /// currently shown (for an instant first frame in the viewer).
    var imageTapped: ((_ imageUrl: URL, _ thumbnailUrl: URL?, _ currentImage: UIImage?) -> Void)?

    /// Invoked when the user taps a video post's poster, carrying the playable
    /// video url.
    var videoTapped: ((_ videoUrl: URL) -> Void)?

    /// Invoked when the user taps "Open in browser" on the image-load failure
    /// plate, carrying the original image url to hand to the system browser.
    var openInBrowser: ((_ url: URL) -> Void)?

    var upvoteTapped: (() -> Void)?
    var downvoteTapped: (() -> Void)?
    var saveTapped: (() -> Void)?

    /// Invoked when the user taps a link inside the post body markdown.
    var onBodyLinkTapped: ((URL) -> Void)?

    /// Invoked when the user taps an inline image in the post body markdown.
    var onBodyImageTapped: ((_ url: URL, _ altText: String?, _ sourceRect: CGRect) -> Void)?

    /// Invoked when the user taps a video link in the post body markdown.
    var onBodyVideoTapped: ((URL) -> Void)?

    /// Invoked when the user taps an audio link in the post body markdown.
    var onBodyAudioTapped: ((URL) -> Void)?

    // MARK: UI Properties

    lazy var mainVerticalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.accessibilityIdentifier = "mainVerticalStackView"

        let subviews = [
            postImageContainer,
            postContentVerticalStackView,
            buttonBarStackView,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        NSLayoutConstraint.activate([
            postImageContainer.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            buttonBarStackView.widthAnchor.constraint(
                equalTo: stackView.widthAnchor, constant: -8 * 2
            ),
            postContentVerticalStackView.widthAnchor.constraint(
                equalTo: stackView.widthAnchor, constant: -8 * 2
            ),
        ])

        return stackView
    }()

    lazy var postImageContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .tertiarySystemGroupedBackground
        view.accessibilityIdentifier = "postImageContainer"
        return view
    }()

    lazy var postImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIdentifier = "postImageView"
        return imageView
    }()

    private lazy var mediaBadgeView = MediaBadgeView()

    private lazy var playIconView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 52, weight: .regular)
        let imageView = UIImageView(image: UIImage(systemName: "play.circle.fill", withConfiguration: configuration))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        imageView.isHidden = true
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowOpacity = 0.5
        imageView.layer.shadowRadius = 4
        imageView.layer.shadowOffset = .zero
        return imageView
    }()

    /// Spins over the image panel while a post image is loading, so the panel
    /// reads as "loading" instead of an empty gap. Sits above `postImageView`
    /// (and any thumbnail painted into it) but ignores touches so the
    /// tap-to-open gesture still reaches the image.
    private lazy var loadingSpinner: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.color = .secondaryLabel
        view.hidesWhenStopped = true
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }()

    lazy var postContentVerticalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        stackView.accessibilityIdentifier = "postContentVerticalStackView"

        let subviews = [
            postImageContainer,
            titleLabel,
            bodyView,
            linkPreviewView,
            attributionLabel,
            subtitleHorizontalStackView,
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

    /// Rendered post-body markdown view. Recreated when the text-size preference
    /// changes, since `MarkdownBodyView` bakes the context (fonts, spacing) at
    /// init time. For a typical session only one instance is ever needed.
    private(set) lazy var bodyView: MarkdownBodyView = makeBodyView(textScale: 0)

    lazy var linkPreviewView: LinkPreviewView = {
        let view = LinkPreviewView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tapped = { [weak self] url in
            self?.linkTapped?(url)
        }
        return view
    }()

    lazy var attributionLabel: LinkLabel = {
        let label = LinkLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.accessibilityIdentifier = "attribution"
        label.linkTextAttributes = [:]
        label.highlightedLinkTextAttributes = [:]
        label.tapped = { [weak self] url in
            self?.linkTapped?(url)
        }
        label.longPressed = { [weak self] url in
            self?.linkLongPressed?(url)
        }
        return label
    }()

    lazy var subtitleHorizontalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 2

        let spacerView = UIView()
        spacerView.backgroundColor = .clear
        spacerView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stackView.addArrangedSubview(subtitleScoreLabel)
        stackView.addArrangedSubview(subtitleCommentLabel)
        stackView.addArrangedSubview(subtitleAgeLabel)
        stackView.addArrangedSubview(spacerView)

        return stackView
    }()

    lazy var subtitleScoreLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        return label
    }()

    lazy var subtitleCommentLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        return label
    }()

    lazy var subtitleAgeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        return label
    }()

    lazy var buttonBarStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.distribution = .fill

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let subviews = [
            upvoteBarButton,
            downvoteBarButton,
            spacer,
            saveBarButton,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        return stackView
    }()

    lazy var upvoteBarButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = Design.Post.upvoteButton.image
        configuration.contentInsets = .init(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.baseBackgroundColor = .clear
        configuration.automaticallyUpdateForSelection = false

        let button = UIButton(configuration: configuration)

        button.addTarget(self, action: #selector(upvoteButtonTapped), for: .touchUpInside)

        button.configurationUpdateHandler = { button in
            guard var newConfiguration = button.configuration else {
                assertionFailure()
                return
            }

            if button.isSelected {
                // The upvoted state follows the user's accent (the design tints
                // every upvote with it), read live so it tracks accent changes.
                newConfiguration.imageColorTransformer = .init { _ in ThemeManager.currentAccentColor }
                newConfiguration.baseBackgroundColor = ThemeManager.currentAccentColor
            }

            button.configuration = newConfiguration
        }

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40),
        ])

        return button
    }()

    lazy var downvoteBarButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = Design.Post.downvoteButton.image
        configuration.contentInsets = .init(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.baseBackgroundColor = .clear
        configuration.automaticallyUpdateForSelection = false

        let button = UIButton(configuration: configuration)

        button.addTarget(self, action: #selector(downvoteButtonTapped), for: .touchUpInside)

        button.configurationUpdateHandler = { button in
            guard var newConfiguration = button.configuration else {
                assertionFailure()
                return
            }

            if button.isSelected {
                newConfiguration.imageColorTransformer = .init { _ in GeneralAppearance.downColor }
                newConfiguration.baseBackgroundColor = GeneralAppearance.downColor
            }

            button.configuration = newConfiguration
        }

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40),
        ])

        return button
    }()

    lazy var saveBarButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = Design.Post.saveButton.image
        configuration.contentInsets = .init(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.baseBackgroundColor = .clear
        configuration.automaticallyUpdateForSelection = false

        let button = UIButton(configuration: configuration)

        button.addTarget(self, action: #selector(saveButtonTapped), for: .touchUpInside)

        button.configurationUpdateHandler = { button in
            guard var newConfiguration = button.configuration else {
                assertionFailure()
                return
            }

            if button.isSelected {
                newConfiguration.image = UIImage(systemName: "bookmark.fill")
                newConfiguration.imageColorTransformer = .init { _ in .systemYellow }
            } else {
                newConfiguration.image = Design.Post.saveButton.image
                newConfiguration.imageColorTransformer = .init { $0 }
            }

            button.configuration = newConfiguration
        }

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40),
        ])

        return button
    }()

    // MARK: Private

    /// Text-scale baked into the current `bodyView`. Compared on each configure;
    /// when it changes a new `MarkdownBodyView` is built and swapped into the
    /// stack view so fonts reflect the updated preference.
    private var bodyViewTextScale: CGFloat = 0

    private var postImageContainerHeightConstraint: NSLayoutConstraint!
    private var imageLoadTask: Task<Void, Never>?

    /// Height reserved for the image panel while the image is still loading and
    /// its real aspect ratio isn't known yet, so the spinner has somewhere to
    /// sit and the panel doesn't collapse to nothing.
    private static let imageLoadingPlaceholderHeight: CGFloat = 200

    /// Retained so a Retry from the failure plate can re-request the image after
    /// `configure` has returned.
    private var imageService: ImageServiceType?

    /// The image-load failure plate, created lazily on first failure and kept
    /// for reuse. Sits on top of `postImageView`, filling `postImageContainer`.
    private var imageFailureView: ImageLoadFailureView?

    /// The full-size image url for the currently-configured post image (set
    /// only for `.post` content), used by the tap-to-open-viewer gesture.
    private var tappableImageUrl: URL?
    private var tappableThumbnailUrl: URL?
    private var tappableVideoUrl: URL?

    /// The post image's pixel dimensions when known (from `image_details`), used
    /// to reserve the exact image height before it loads. nil when unknown.
    private var postImageSize: CGSize?

    // MARK: Functions

    /// Pins the body to the full content width of `postContentVerticalStackView`.
    /// That stack is `.leading`-aligned so siblings (the link preview, subtitle)
    /// keep their intrinsic width; without this constraint the body would inherit
    /// that behavior and shrink to its own intrinsic size whenever
    /// `MarkdownBodyView` invalidates it after an inline image loads — collapsing
    /// the whole body into a narrow column. Re-applied to each rebuilt body view.
    private func pinBodyWidth(_ body: MarkdownBodyView) {
        body.widthAnchor.constraint(equalTo: postContentVerticalStackView.widthAnchor).isActive = true
    }

    private func makeBodyView(textScale: CGFloat) -> MarkdownBodyView {
        let context = MarkdownContext(kind: .post, textScale: textScale, density: .comfortable)
        let view = MarkdownBodyView(context: context)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "body"
        view.delegate = self
        view.onContentSizeChange = { [weak self] in
            self?.adjustHeightForChange()
        }
        return view
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        accessibilityIdentifier = "postDetailHeader"

        selectionStyle = .none

        postImageContainer.addSubview(postImageView)
        postImageContainer.addSubview(mediaBadgeView)
        postImageContainer.addSubview(playIconView)
        postImageContainer.addSubview(loadingSpinner)
        contentView.addSubview(mainVerticalStackView)

        let postImageContainerHeightConstraint = postImageContainer.heightAnchor.constraint(equalToConstant: 0)
        self.postImageContainerHeightConstraint = postImageContainerHeightConstraint

        let linkPreviewWidthConstraint = linkPreviewView.widthAnchor.constraint(equalToConstant: 200)
        linkPreviewWidthConstraint.priority = .defaultLow
        let linkPreviewTrailingConstraint = linkPreviewView.trailingAnchor.constraint(lessThanOrEqualTo: mainVerticalStackView.trailingAnchor, constant: -8)

        NSLayoutConstraint.activate([
            mainVerticalStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainVerticalStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainVerticalStackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainVerticalStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            linkPreviewWidthConstraint,
            linkPreviewTrailingConstraint,

            postImageView.leadingAnchor.constraint(equalTo: postImageContainer.leadingAnchor),
            postImageView.trailingAnchor.constraint(equalTo: postImageContainer.trailingAnchor),
            postImageView.topAnchor.constraint(equalTo: postImageContainer.topAnchor),
            postImageView.bottomAnchor.constraint(equalTo: postImageContainer.bottomAnchor),

            mediaBadgeView.leadingAnchor.constraint(equalTo: postImageContainer.leadingAnchor, constant: 8),
            mediaBadgeView.bottomAnchor.constraint(equalTo: postImageContainer.bottomAnchor, constant: -8),

            playIconView.centerXAnchor.constraint(equalTo: postImageView.centerXAnchor),
            playIconView.centerYAnchor.constraint(equalTo: postImageView.centerYAnchor),

            loadingSpinner.centerXAnchor.constraint(equalTo: postImageContainer.centerXAnchor),
            loadingSpinner.centerYAnchor.constraint(equalTo: postImageContainer.centerYAnchor),

            postImageContainerHeightConstraint,
        ])

        pinBodyWidth(bodyView)

        let contextMenuIteraction = UIContextMenuInteraction(delegate: self)
        linkPreviewView.addInteraction(contextMenuIteraction)

        postImageView.isUserInteractionEnabled = true
        let imageTap = UITapGestureRecognizer(target: self, action: #selector(postImageTapped))
        postImageView.addGestureRecognizer(imageTap)

        prepareForReuse()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        imageLoadTask?.cancel()
        imageLoadTask = nil

        tappableImageUrl = nil
        tappableThumbnailUrl = nil
        tappableVideoUrl = nil
        postImageSize = nil

        linkTapped = nil
        linkLongPressed = nil
        linkTappedFromPreview = nil
        imageTapped = nil
        videoTapped = nil
        openInBrowser = nil

        onBodyLinkTapped = nil
        onBodyImageTapped = nil
        onBodyVideoTapped = nil
        onBodyAudioTapped = nil

        bodyView.setBlocks([])

        linkPreviewView.isHidden = true
        linkPreviewView.prepareForReuse()

        mediaBadgeView.text = nil
        playIconView.isHidden = true
        postImageContainer.isHidden = true
        postImageContainer.backgroundColor = .clear
        postImageView.image = nil
        postImageView.isHidden = false
        loadingSpinner.stopAnimating()

        imageFailureView?.isHidden = true
        imageFailureView?.onRetry = nil
        imageFailureView?.onOpenInBrowser = nil
        imageFailureView?.setRetrying(false)
    }

    func configure(with viewModel: PostDetailHeaderViewModel, imageService: ImageServiceType) {
        self.imageService = imageService
        titleLabel.attributedText = viewModel.title

        // Rebuild the body view when the text-scale preference changes so fonts
        // are correct; otherwise reuse the existing instance.
        let textScale = viewModel.textSizeAdjustment
        if textScale != bodyViewTextScale {
            let oldBodyView = bodyView
            let newBodyView = makeBodyView(textScale: textScale)
            if let idx = postContentVerticalStackView.arrangedSubviews.firstIndex(of: oldBodyView) {
                postContentVerticalStackView.insertArrangedSubview(newBodyView, at: idx)
                oldBodyView.removeFromSuperview()
                pinBodyWidth(newBodyView)
            }
            bodyView = newBodyView
            bodyViewTextScale = textScale
        }

        bodyView.imageLoader = { [imageService] url in
            for await state in imageService.fetch(url) {
                if case let .ready(image) = state { return image }
            }
            return nil
        }
        bodyView.setBlocks(viewModel.bodyBlocks)
        attributionLabel.attributedText = viewModel.attribution
        subtitleScoreLabel.attributedText = viewModel.subtitleScore
        subtitleCommentLabel.attributedText = viewModel.subtitleComments
        subtitleAgeLabel.attributedText = viewModel.subtitleAge

        upvoteBarButton.isSelected = viewModel.isUpvoted
        downvoteBarButton.isSelected = viewModel.isDownvoted
        saveBarButton.isSelected = viewModel.isSaved

        // State-aware VoiceOver labels for the action bar.
        upvoteBarButton.accessibilityLabel = VoteAccessibility.upvoteButtonLabel(isUpvoted: viewModel.isUpvoted)
        downvoteBarButton.accessibilityLabel = VoteAccessibility.downvoteButtonLabel(isDownvoted: viewModel.isDownvoted)
        saveBarButton.accessibilityLabel = VoteAccessibility.saveButtonLabel(isSaved: viewModel.isSaved)

        // The visible subtitle is an icon-and-value run; give VoiceOver a clean
        // spoken form. The title is plain text and reads as-is.
        subtitleScoreLabel.accessibilityLabel = viewModel.subtitleScoreAccessibilityLabel
        subtitleCommentLabel.accessibilityLabel = viewModel.subtitleCommentsAccessibilityLabel
        subtitleAgeLabel.accessibilityLabel = viewModel.subtitleAgeAccessibilityLabel

        imageLoadTask?.cancel()
        mediaBadgeView.text = nil
        playIconView.isHidden = true
        tappableVideoUrl = nil
        postImageContainer.backgroundColor = .clear
        imageFailureView?.isHidden = true
        postImageView.isHidden = false
        switch viewModel.image {
        case .none:
            postImageContainer.isHidden = true
            linkPreviewView.isHidden = true

        case let .post(imageUrl, thumbnailUrl, imageSize):
            linkPreviewView.isHidden = true
            tappableImageUrl = imageUrl
            tappableThumbnailUrl = thumbnailUrl
            postImageSize = imageSize
            mediaBadgeView.text = imageUrl.isAnimatedImage ? "GIF" : nil
            postImageView.isAccessibilityElement = true
            postImageView.accessibilityLabel = NSLocalizedString(
                "Post image",
                comment: "VoiceOver label for the post's image"
            )
            postImageView.accessibilityHint = NSLocalizedString(
                "Opens the full-size image",
                comment: "VoiceOver hint for the post image"
            )
            postImageView.accessibilityTraits = [.image, .button]
            loadPostImage(imageUrl: imageUrl, thumbnailUrl: thumbnailUrl)

        case let .video(videoUrl, thumbnailUrl):
            linkPreviewView.isHidden = true
            tappableVideoUrl = videoUrl
            playIconView.isHidden = false
            postImageView.isAccessibilityElement = true
            postImageView.accessibilityLabel = NSLocalizedString(
                "Video",
                comment: "VoiceOver label for the post's video"
            )
            postImageView.accessibilityHint = NSLocalizedString(
                "Plays the video",
                comment: "VoiceOver hint for the post video"
            )
            postImageView.accessibilityTraits = [.image, .button]
            if let thumbnailUrl {
                imageLoadTask = Task { [weak self] in
                    for await state in imageService.fetch(thumbnailUrl) {
                        if Task.isCancelled { return }
                        guard let self else { return }
                        if case let .ready(image) = state { setImage(image) }
                    }
                }
            } else {
                // No poster frame: show a neutral panel behind the play button.
                postImageView.image = nil
                postImageContainer.isHidden = false
                postImageContainer.backgroundColor = .secondarySystemBackground
                postImageContainerHeightConstraint.constant = 200
                adjustHeightForChange()
            }

        case let .linkPreview(url, thumbnailUrl):
            postImageContainer.isHidden = true
            linkPreviewView.isHidden = false
            linkPreviewView.url = url
            if let thumbnailUrl {
                imageLoadTask = Task { [weak self] in
                    for await state in imageService.fetch(thumbnailUrl) {
                        if Task.isCancelled { return }
                        guard let self else { return }
                        switch state {
                        case let .ready(image):
                            linkPreviewView.thumbnailImage = image
                            adjustHeightForChange()
                        case .loading, .failure:
                            break
                        }
                    }
                }
            }
            adjustHeightForChange()
        }
    }

    /// Fetches the post image, driving the header through loading → ready /
    /// failure. Reused by the failure plate's Retry.
    private func loadPostImage(imageUrl: URL, thumbnailUrl: URL?) {
        guard let imageService else { return }
        imageLoadTask?.cancel()

        // On a fresh load reserve a neutral panel with a spinner, so the image's
        // arrival doesn't jump the layout from text-only to full-size and the
        // user can see something is happening. During a retry the failure plate
        // shows its own "Loading image…" spinner, so leave it in place.
        let isRetrying = imageFailureView.map { !$0.isHidden } ?? false
        if !isRetrying {
            showImageLoadingPlaceholder(imageUrl: imageUrl, thumbnailUrl: thumbnailUrl)
        }

        // Once the full image is shown, ignore a thumbnail that lost the race and
        // arrives late (the fetch yields them on separate tasks).
        var fullImageShown = false
        imageLoadTask = Task { [weak self] in
            for await state in imageService.fetch(imageUrl, thumbnail: thumbnailUrl) {
                if Task.isCancelled { return }
                guard let self else { return }
                switch state {
                case let .loading(thumbnailImage):
                    guard !fullImageShown, let thumbnailImage else { break }
                    // A low-res preview arrived before the full image: paint it
                    // under the still-spinning indicator.
                    setImage(thumbnailImage)
                    setImageLoadingSpinnerVisible(true)
                case let .ready(image):
                    fullImageShown = true
                    setImage(image)
                    setImageLoadingSpinnerVisible(false)
                    postImageContainer.backgroundColor = .clear
                case .failure:
                    setImageLoadingSpinnerVisible(false)
                    // Keep a thumbnail if we already have one; otherwise put the
                    // failure plate in the image's place.
                    if postImageView.image == nil {
                        showImageFailure(imageUrl: imageUrl, thumbnailUrl: thumbnailUrl)
                    }
                }
            }
        }
    }

    /// Reserves a panel sized for the image and starts the spinner, shown from
    /// the moment a post image starts loading until it arrives.
    private func showImageLoadingPlaceholder(imageUrl: URL, thumbnailUrl: URL?) {
        imageFailureView?.isHidden = true
        postImageView.isHidden = false
        postImageView.image = nil
        playIconView.isHidden = true
        postImageContainer.isHidden = false
        postImageContainer.backgroundColor = .secondarySystemBackground
        postImageContainerHeightConstraint.constant = reservedImageHeight(
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl
        )
        setImageLoadingSpinnerVisible(true)
        adjustHeightForChange()
    }

    /// The height to reserve for the image while it loads. When the image service
    /// has already decoded this image (or its thumbnail) — e.g. the post list
    /// fetched the thumbnail before the user opened the post — its aspect ratio
    /// is known, so reserve the exact final height and the image won't resize the
    /// row when it appears. Otherwise fall back to a neutral placeholder height.
    private func reservedImageHeight(imageUrl: URL, thumbnailUrl: URL?) -> CGFloat {
        // Prefer the dimensions the server reported (`image_details`) — they're
        // available even on cold paths (deep links, the widget, or before the
        // list fetched a thumbnail). Fall back to a size the image service has
        // already decoded, then to a neutral placeholder height.
        let knownSize = postImageSize
            ?? imageService?.imageSize(for: imageUrl)
            ?? thumbnailUrl.flatMap { imageService?.imageSize(for: $0) }
        guard let knownSize, knownSize.width > 0, knownSize.height > 0 else {
            return Self.imageLoadingPlaceholderHeight
        }
        let cellWidth = tableView?.bounds.width ?? 100
        let maxImageHeight = (tableView?.bounds.height ?? 800) * 0.6
        let aspectRatio = knownSize.width / knownSize.height
        return min(cellWidth / aspectRatio, maxImageHeight)
    }

    private func setImageLoadingSpinnerVisible(_ visible: Bool) {
        if visible {
            loadingSpinner.startAnimating()
        } else {
            loadingSpinner.stopAnimating()
        }
    }

    /// Shows the failure plate in the image's place, wired to retry the same
    /// image or hand its original url to the browser.
    private func showImageFailure(imageUrl: URL, thumbnailUrl: URL?) {
        let failureView = installedImageFailureView()
        failureView.onRetry = { [weak self] in
            guard let self else { return }
            Haptics.tap()
            failureView.setRetrying(true)
            loadPostImage(imageUrl: imageUrl, thumbnailUrl: thumbnailUrl)
        }
        failureView.onOpenInBrowser = { [weak self] in
            guard let self else { return }
            // Unwrap a Lemmy image-proxy url so the browser opens the real image.
            openInBrowser?(imageUrl.lemmyImageProxyOriginalUrl ?? imageUrl)
        }
        failureView.setRetrying(false)
        failureView.isHidden = false

        postImageView.isHidden = true
        postImageView.image = nil
        playIconView.isHidden = true
        mediaBadgeView.text = nil
        postImageContainer.isHidden = false

        let width = tableView?.bounds.width ?? bounds.width
        let fittingHeight = failureView.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        postImageContainerHeightConstraint.constant = max(ImageLoadFailureView.minimumHeight, fittingHeight)

        adjustHeightForChange()
    }

    /// Lazily installs the failure plate, filling `postImageContainer` above the
    /// image view.
    private func installedImageFailureView() -> ImageLoadFailureView {
        if let imageFailureView { return imageFailureView }
        let view = ImageLoadFailureView()
        view.translatesAutoresizingMaskIntoConstraints = false
        postImageContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: postImageContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: postImageContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: postImageContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: postImageContainer.bottomAnchor),
        ])
        imageFailureView = view
        return view
    }

    private func setImage(_ image: UIImage) {
        let wasShowingFailure = imageFailureView.map { !$0.isHidden } ?? false
        imageFailureView?.isHidden = true
        postImageView.isHidden = false
        postImageContainer.isHidden = false

        if wasShowingFailure {
            UIView.transition(with: postImageView, duration: 0.25, options: .transitionCrossDissolve) {
                self.postImageView.image = image
            }
        } else {
            postImageView.image = image
        }

        let cellWidth = tableView?.bounds.width ?? 100
        let maxImageHeight = (tableView?.bounds.height ?? 800) * 0.6
        let imageFittingHeight = image.fittingHeight(for: cellWidth)
        let imageHeight = min(imageFittingHeight, maxImageHeight)

        postImageContainerHeightConstraint.constant = imageHeight

        adjustHeightForChange()
    }

    private func adjustHeightForChange() {
        guard !isBeingConfigured else { return }
        // Re-measure the row height in place, but WITHOUT the default
        // begin/endUpdates animation. An async image (or its thumbnail) arriving
        // while the detail is being pushed would otherwise animate the header
        // growing from its placeholder height — reading as the whole header
        // zooming in mid-push (and twice over, as the thumbnail then the full
        // image land). Snapping matches the deliberately non-animated
        // applySnapshot() in PostDetailViewController, made for the same reason.
        UIView.performWithoutAnimation {
            tableView?.beginUpdates()
            tableView?.endUpdates()
        }
    }

    @objc
    private func postImageTapped() {
        if let tappableVideoUrl {
            videoTapped?(tappableVideoUrl)
        } else if let tappableImageUrl {
            imageTapped?(tappableImageUrl, tappableThumbnailUrl, postImageView.image)
        }
    }

    @objc
    private func upvoteButtonTapped() {
        upvoteTapped?()
    }

    @objc
    private func downvoteButtonTapped() {
        downvoteTapped?()
    }

    @objc
    private func saveButtonTapped() {
        saveTapped?()
    }
}

extension PostDetailHeaderCell: MarkdownBodyDelegate {
    func markdownBody(didTapLink url: URL) {
        onBodyLinkTapped?(url)
    }

    func markdownBody(didTapImage url: URL, altText: String?, sourceRect: CGRect) {
        onBodyImageTapped?(url, altText, sourceRect)
    }

    func markdownBody(didTapVideo url: URL) {
        onBodyVideoTapped?(url)
    }

    func markdownBody(didTapAudio url: URL) {
        onBodyAudioTapped?(url)
    }
}

extension PostDetailHeaderCell: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            let url = linkPreviewView.url,
            let appService
        else { return nil }

        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: {
                appService.safariViewControllerForPreview(url: url)
            },
            actionProvider: nil
        )
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionCommitAnimating
    ) {
        guard
            let safariVC = animator.previewViewController as? SFSafariViewController
        else {
            logger.assertionFailure()
            return
        }
        animator.addCompletion { [weak self] in
            self?.linkTappedFromPreview?(safariVC)
        }
    }
}
