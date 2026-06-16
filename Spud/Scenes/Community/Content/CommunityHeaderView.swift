//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudMarkdownKit
import SpudUIKit
import UIKit

/// Apollo-style community header: banner image, overlapping circular icon,
/// title, "!name@instance" handle, subscriber/post counts, a markdown
/// description, and a prominent state-aware Subscribe/Unsubscribe button.
///
/// Layout-only; the owning view controller drives it via `configure(...)`,
/// loads images, and wires the button / description-link callbacks.
final class CommunityHeaderView: UIView {
    /// Fired when the Subscribe/Unsubscribe button is tapped.
    var subscribeTapped: (() -> Void)?
    /// Fired when a link inside the markdown description is tapped (raw renderer
    /// URL; the host resolves `spud-markdown://` mentions).
    var onBodyLinkTapped: ((URL) -> Void)?
    /// Fired when a loaded inline description image is tapped (zoom).
    var onBodyImageTapped: ((_ url: URL, _ altText: String?, _ sourceRect: CGRect) -> Void)?
    /// Fired when an inline description video tile is tapped.
    var onBodyVideoTapped: ((URL) -> Void)?
    /// Fired when an inline description audio tile is tapped.
    var onBodyAudioTapped: ((URL) -> Void)?

    /// The image loader used for inline description images. Set by the owning
    /// view controller before `configure(...)`.
    var imageService: ImageServiceType?

    /// Fired when an inline description image finishes loading and the header's
    /// height changes, so the host can re-measure its scrolling table header.
    var onBodyImageLoaded: (() -> Void)?

    private let bannerHeight: CGFloat = 120
    private let iconSize: CGFloat = 64

    // MARK: Subviews

    private lazy var bannerImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = .secondarySystemBackground
        return view
    }()

    private lazy var iconImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = iconSize / 2
        view.layer.borderWidth = 3
        view.layer.borderColor = UIColor.systemBackground.cgColor
        view.backgroundColor = .tertiarySystemBackground
        view.image = UIImage(systemName: "person.3.fill")
        view.tintColor = .secondaryLabel
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.font = UIFont.boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .title2).pointSize)
        label.numberOfLines = 2
        return label
    }()

    private lazy var handleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        return label
    }()

    private lazy var statsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        return label
    }()

    /// Network-activity line (weekly / monthly active users) from the Explorer
    /// directory. Hidden when the community isn't in the directory.
    private lazy var vitalityLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.isHidden = true
        return label
    }()

    /// Stacks the subscriber/post counts above the vitality line so the latter
    /// collapses cleanly when there's no Explorer data.
    private lazy var metaStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [statsLabel, vitalityLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 3
        stack.alignment = .leading
        return stack
    }()

    private lazy var descriptionView: MarkdownBodyView = {
        let context = MarkdownContext(kind: .post, textScale: 0, density: .comfortable)
        let view = MarkdownBodyView(context: context)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "description"
        view.delegate = self
        view.onContentSizeChange = { [weak self] in
            self?.onBodyImageLoaded?()
        }
        return view
    }()

    private lazy var subscribeButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .medium
        config.buttonSize = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(subscribeButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var separator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }()

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Re-evaluate the border color in case the trait collection (light /
        // dark) changed.
        iconImageView.layer.borderColor = UIColor.systemBackground.cgColor
    }

    private func setup() {
        backgroundColor = Theme.background

        addSubview(bannerImageView)
        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(handleLabel)
        addSubview(metaStack)
        addSubview(subscribeButton)
        addSubview(descriptionView)
        addSubview(separator)

        let margin: CGFloat = 16

        NSLayoutConstraint.activate([
            bannerImageView.topAnchor.constraint(equalTo: topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerImageView.heightAnchor.constraint(equalToConstant: bannerHeight),

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            iconImageView.centerYAnchor.constraint(equalTo: bannerImageView.bottomAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: iconSize),

            subscribeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            subscribeButton.topAnchor.constraint(equalTo: bannerImageView.bottomAnchor, constant: 8),

            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),

            handleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            handleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            handleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),

            metaStack.topAnchor.constraint(equalTo: handleLabel.bottomAnchor, constant: 6),
            metaStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            metaStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),

            descriptionView.topAnchor.constraint(equalTo: metaStack.bottomAnchor, constant: 12),
            descriptionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            descriptionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),

            separator.topAnchor.constraint(equalTo: descriptionView.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: Configuration

    func configure(
        title: String,
        qualifiedName: String,
        subscribersText: String,
        postsText: String,
        vitalityText: String?,
        descriptionMarkdown: String?,
        subscribed: CommunitySubscribedState
    ) {
        titleLabel.text = title
        handleLabel.text = qualifiedName

        let subscribers = String(
            format: NSLocalizedString("%@ subscribers", comment: "Community header subscriber count"),
            subscribersText
        )
        let posts = String(
            format: NSLocalizedString("%@ posts", comment: "Community header post count"),
            postsText
        )
        statsLabel.text = "\(subscribers)  ·  \(posts)"

        vitalityLabel.text = vitalityText
        vitalityLabel.isHidden = vitalityText == nil

        configureDescription(markdown: descriptionMarkdown)
        configureSubscribeButton(subscribed: subscribed)
    }

    private func configureDescription(markdown: String?) {
        guard let markdown, !markdown.isEmpty else {
            descriptionView.setBlocks([])
            descriptionView.isHidden = true
            return
        }
        descriptionView.isHidden = false
        // Set the loader before the blocks so inline images start loading as the
        // image blocks are built.
        if let imageService {
            descriptionView.imageLoader = { [imageService] url in
                for await state in imageService.fetch(url) {
                    if case let .ready(image) = state { return image }
                }
                return nil
            }
        }
        descriptionView.setBlocks(MarkdownBlockCache.shared.blocks(for: markdown))
    }

    private func configureSubscribeButton(subscribed: CommunitySubscribedState) {
        var config = subscribeButton.configuration ?? .filled()
        switch subscribed {
        case .notSubscribed:
            config.title = NSLocalizedString("Subscribe", comment: "Community subscribe button")
            config.image = UIImage(systemName: "plus")
            config.baseBackgroundColor = .systemBlue
            config.baseForegroundColor = .white
            subscribeButton.isEnabled = true
        case .subscribed:
            config.title = NSLocalizedString("Subscribed", comment: "Community unsubscribe button")
            config.image = UIImage(systemName: "checkmark")
            config.baseBackgroundColor = .secondarySystemBackground
            config.baseForegroundColor = .label
            subscribeButton.isEnabled = true
        case .pending:
            config.title = NSLocalizedString("Pending", comment: "Community pending-subscription button")
            config.image = UIImage(systemName: "clock")
            config.baseBackgroundColor = .secondarySystemBackground
            config.baseForegroundColor = .secondaryLabel
            subscribeButton.isEnabled = true
        }
        config.imagePadding = 4
        subscribeButton.configuration = config
    }

    // MARK: Images

    func setBannerImage(_ image: UIImage?) {
        bannerImageView.image = image
    }

    func setIconImage(_ image: UIImage?) {
        guard let image else { return }
        iconImageView.image = image
    }

    @objc
    private func subscribeButtonTapped() {
        subscribeTapped?()
    }
}

extension CommunityHeaderView: MarkdownBodyDelegate {
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
