//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Down
import Foundation
import LemmyKit
import SpudDataKit
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
    /// Fired when a link inside the markdown description is tapped.
    var linkTapped: ((URL) -> Void)?

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

    private lazy var descriptionLabel: LinkLabel = {
        let label = LinkLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.numberOfLines = 0
        label.tapped = { [weak self] url in
            self?.linkTapped?(url)
        }
        return label
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
        backgroundColor = .systemBackground

        addSubview(bannerImageView)
        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(handleLabel)
        addSubview(statsLabel)
        addSubview(subscribeButton)
        addSubview(descriptionLabel)
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

            statsLabel.topAnchor.constraint(equalTo: handleLabel.bottomAnchor, constant: 6),
            statsLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            statsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),

            descriptionLabel.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            descriptionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),

            separator.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 12),
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

        configureDescription(markdown: descriptionMarkdown)
        configureSubscribeButton(subscribed: subscribed)
    }

    private func configureDescription(markdown: String?) {
        guard let markdown, !markdown.isEmpty else {
            descriptionLabel.attributedText = NSAttributedString(string: "")
            descriptionLabel.isHidden = true
            return
        }
        descriptionLabel.isHidden = false
        let config = PostDetailAppearance.bodyStylerConfiguration(for: 0)
        descriptionLabel.attributedText = Down(markdownString: markdown)
            .toAttributedString(styler: DownStyler(configuration: config))
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
