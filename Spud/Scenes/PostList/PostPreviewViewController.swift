//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudMarkdownKit
import SpudUIKit
import SpudUtilKit
import UIKit

/// Compact post preview shown as the floating peek above a feed post's context
/// menu (Apollo signature). Renders the post image (for image posts), title and
/// full body — the feed cell truncates the body, so the peek is where you read
/// it without opening the post. Self-sizes via `preferredContentSize`.
final class PostPreviewViewController: UIViewController {
    private let row: PostListRow
    private let imageService: ImageServiceType
    private let postContentDetector: PostContentDetectorServiceType
    private let textSizeAdjustment: CGFloat

    private var loadTask: Task<Void, Never>?

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.layer.cornerCurve = .continuous
        imageView.isHidden = true
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 4
        label.font = .preferredFont(forTextStyle: .headline)
        return label
    }()

    /// The peek mirrors the real post body using the same `MarkdownBodyView`
    /// renderer as post detail, but is a transient preview, so it is
    /// height-capped: a long post fades out past `maxBodyHeight` instead of
    /// growing the popover without bound.
    private let bodyContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        return view
    }()

    private lazy var bodyView: MarkdownBodyView = {
        let context = MarkdownContext(kind: .post, textScale: textSizeAdjustment, density: .comfortable)
        let view = MarkdownBodyView(context: context)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "body"
        return view
    }()

    private let maxBodyHeight: CGFloat = 340

    /// Alpha mask that fades the body's bottom edge when it overflows the cap.
    /// Alpha-based (not a color), so it is correct in both light and dark.
    private let fadeMaskLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor]
        return layer
    }()

    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 10
        return stackView
    }()

    private lazy var imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 0)

    init(
        row: PostListRow,
        imageService: ImageServiceType,
        postContentDetector: PostContentDetectorServiceType,
        textSizeAdjustment: CGFloat
    ) {
        self.row = row
        self.imageService = imageService
        self.postContentDetector = postContentDetector
        self.textSizeAdjustment = textSizeAdjustment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .secondarySystemGroupedBackground
        view.accessibilityIdentifier = "postPreview"
        titleLabel.accessibilityIdentifier = "postPreviewTitle"

        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(bodyContainer)
        view.addSubview(stackView)

        bodyContainer.addSubview(bodyView)
        let bodyBottom = bodyView.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor)
        bodyBottom.priority = .defaultLow
        NSLayoutConstraint.activate([
            bodyView.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            bodyView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            bodyBottom,
            bodyContainer.heightAnchor.constraint(lessThanOrEqualToConstant: maxBodyHeight),
        ])

        let margin: CGFloat = 14
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: margin),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -margin),
        ])

        titleLabel.text = row.title

        if let body = row.body, !body.isEmpty {
            bodyView.imageLoader = { [imageService] url in
                for await state in imageService.fetch(url) {
                    if case let .ready(image) = state { return image }
                }
                return nil
            }
            bodyView.setBlocks(MarkdownBlockCache.shared.blocks(for: body))
        } else {
            bodyContainer.isHidden = true
        }

        configureImage()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateBodyFade()

        // Size the popover to the content. The width is whatever the system
        // offers (the cell width); the height is the fitted stack height.
        let targetWidth = view.bounds.width > 0 ? view.bounds.width : 320
        let fittingSize = view.systemLayoutSizeFitting(
            CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        if preferredContentSize != fittingSize {
            preferredContentSize = fittingSize
        }
    }

    /// Fades the body's bottom edge only when the rendered body is taller than
    /// the cap (i.e. the peek truncated it); otherwise no mask, so a short body
    /// shows in full.
    private func updateBodyFade() {
        let containerHeight = bodyContainer.bounds.height
        let isTruncated = bodyView.bounds.height > containerHeight + 1
        guard isTruncated, containerHeight > 0 else {
            bodyContainer.layer.mask = nil
            return
        }
        let fade: CGFloat = 36
        let start = max(0, (containerHeight - fade) / containerHeight)
        fadeMaskLayer.frame = bodyContainer.bounds
        fadeMaskLayer.locations = [0, NSNumber(value: Double(start)), 1]
        bodyContainer.layer.mask = fadeMaskLayer
    }

    private func configureImage() {
        let url = row.url.flatMap { URL(string: $0) }
        let thumbnailUrl = row.thumbnailUrl.flatMap { URL(string: $0) }

        // Peek the post's image, or a video's poster frame.
        let loadUrl: URL
        switch postContentDetector.contentTypeForUrl(
            url: url,
            thumbnailUrl: thumbnailUrl,
            embedTitle: row.urlEmbedTitle,
            embedDescription: row.urlEmbedDescription
        ) {
        case let .image(image):
            loadUrl = image.thumbnailUrl ?? image.imageUrl
        case let .video(video):
            guard let poster = video.thumbnailUrl else { return }
            loadUrl = poster
        case .externalLink, .textOrEmpty:
            return
        }

        imageView.isHidden = false
        // A 16:9 letterbox keeps the peek a sensible height regardless of the
        // source aspect ratio.
        imageHeightConstraint.constant = 180
        imageHeightConstraint.isActive = true

        loadTask = Task { [weak self] in
            guard let self else { return }
            for await state in imageService.fetch(loadUrl) {
                if Task.isCancelled { return }
                if case let .ready(loaded) = state {
                    imageView.image = loaded
                }
            }
        }
    }
}
