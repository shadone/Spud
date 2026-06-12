//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import OSLog
import SafariServices
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

private let logger = Logger.app

class PostDetailHeaderCell: UITableViewCellBase {
    static let reuseIdentifier = "PostDetailHeaderCell"

    // MARK: Public

    var linkTapped: ((URL) -> Void)?
    var linkTappedFromPreview: ((SFSafariViewController) -> Void)?
    var appService: AppServiceType?

    /// Invoked when the user taps the post's main image, carrying the
    /// full-size image url, optional thumbnail url, and whatever image is
    /// currently shown (for an instant first frame in the viewer).
    var imageTapped: ((_ imageUrl: URL, _ thumbnailUrl: URL?, _ currentImage: UIImage?) -> Void)?

    var upvoteTapped: (() -> Void)?
    var downvoteTapped: (() -> Void)?
    var saveTapped: (() -> Void)?

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
            bodyLabel,
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

    lazy var bodyLabel: LinkLabel = {
        let label = LinkLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.accessibilityIdentifier = "body"
        label.tapped = { [weak self] url in
            self?.linkTapped?(url)
        }
        return label
    }()

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
                newConfiguration.imageColorTransformer = .init { _ in .systemRed }
                newConfiguration.baseBackgroundColor = .systemRed
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

        let button = UIButton(configuration: configuration)

        button.addTarget(self, action: #selector(downvoteButtonTapped), for: .touchUpInside)

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

    private var postImageContainerHeightConstraint: NSLayoutConstraint!
    private var imageLoadTask: Task<Void, Never>?

    /// The full-size image url for the currently-configured post image (set
    /// only for `.post` content), used by the tap-to-open-viewer gesture.
    private var tappableImageUrl: URL?
    private var tappableThumbnailUrl: URL?

    // MARK: Functions

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        accessibilityIdentifier = "postDetailHeader"

        selectionStyle = .none

        postImageContainer.addSubview(postImageView)
        postImageContainer.addSubview(mediaBadgeView)
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

            postImageContainerHeightConstraint,
        ])

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

        linkTapped = nil
        linkTappedFromPreview = nil
        imageTapped = nil

        linkPreviewView.isHidden = true
        linkPreviewView.prepareForReuse()

        mediaBadgeView.text = nil
        postImageContainer.isHidden = true
        postImageView.image = nil
    }

    func configure(with viewModel: PostDetailHeaderViewModel, imageService: ImageServiceType) {
        titleLabel.attributedText = viewModel.title
        bodyLabel.attributedText = viewModel.body
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
        switch viewModel.image {
        case .none:
            postImageContainer.isHidden = true
            linkPreviewView.isHidden = true

        case let .post(imageUrl, thumbnailUrl):
            linkPreviewView.isHidden = true
            tappableImageUrl = imageUrl
            tappableThumbnailUrl = thumbnailUrl
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
            imageLoadTask = Task { [weak self] in
                for await state in imageService.fetch(imageUrl, thumbnail: thumbnailUrl) {
                    if Task.isCancelled { return }
                    guard let self else { return }
                    switch state {
                    case let .loading(thumbnailImage):
                        if let thumbnailImage { setImage(thumbnailImage) }
                    case let .ready(image):
                        setImage(image)
                    case .failure:
                        break
                    }
                }
            }

        case let .linkPreview(url, thumbnailUrl):
            postImageContainer.isHidden = true
            linkPreviewView.url = url
            linkPreviewView.isHidden = false
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

    private func setImage(_ image: UIImage) {
        postImageView.image = image
        postImageContainer.isHidden = false

        let cellWidth = tableView?.bounds.width ?? 100
        let maxImageHeight = (tableView?.bounds.height ?? 800) * 0.6
        let imageFittingHeight = image.fittingHeight(for: cellWidth)
        let imageHeight = min(imageFittingHeight, maxImageHeight)

        postImageContainerHeightConstraint.constant = imageHeight

        adjustHeightForChange()
    }

    private func adjustHeightForChange() {
        guard !isBeingConfigured else { return }
        tableView?.beginUpdates()
        tableView?.endUpdates()
    }

    @objc
    private func postImageTapped() {
        guard let tappableImageUrl else { return }
        imageTapped?(tappableImageUrl, tappableThumbnailUrl, postImageView.image)
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
