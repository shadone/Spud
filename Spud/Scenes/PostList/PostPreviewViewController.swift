//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Down
import SpudDataKit
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

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 12
        return label
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

        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(bodyLabel)
        view.addSubview(stackView)

        let margin: CGFloat = 14
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: margin),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -margin),
        ])

        titleLabel.text = row.title

        if let body = row.body, !body.isEmpty {
            bodyLabel.attributedText = MarkdownRenderer.shared.attributedString(
                markdown: body,
                key: MarkdownRenderer.postBodyKey(markdown: body, textSizeAdjustment: textSizeAdjustment),
                makeStyler: {
                    DownStyler(configuration: PostDetailAppearance.bodyStylerConfiguration(
                        for: textSizeAdjustment
                    ))
                }
            )
        } else {
            bodyLabel.isHidden = true
        }

        configureImage()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

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

    private func configureImage() {
        let url = row.url.flatMap { URL(string: $0) }
        let thumbnailUrl = row.thumbnailUrl.flatMap { URL(string: $0) }
        guard case let .image(image) = postContentDetector.contentTypeForUrl(
            url: url,
            thumbnailUrl: thumbnailUrl,
            embedTitle: row.urlEmbedTitle,
            embedDescription: row.urlEmbedDescription
        ) else {
            return
        }

        imageView.isHidden = false
        // A 16:9 letterbox keeps the peek a sensible height regardless of the
        // source aspect ratio.
        imageHeightConstraint.constant = 180
        imageHeightConstraint.isActive = true

        let loadUrl = image.thumbnailUrl ?? image.imageUrl
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
