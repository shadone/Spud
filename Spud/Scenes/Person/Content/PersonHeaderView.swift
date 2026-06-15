//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUIKit
import UIKit

/// Apollo-style person header: optional banner image, overlapping circular
/// avatar, display name, "@name@instance" handle, a stats line with post /
/// comment karma and the account's cake day, and a markdown bio.
///
/// Layout-only; the owning view controller drives it via `configure(...)`,
/// loads images, and wires the bio-link callback.
final class PersonHeaderView: UIView {
    /// Fired when a link inside the markdown bio is tapped.
    var linkTapped: ((URL) -> Void)?

    /// The image loader used for inline bio images. Set by the owning view
    /// controller before `configure(...)`.
    var imageService: ImageServiceType?

    /// Fired when an inline bio image finishes loading and the bio's height
    /// changes, so the host can re-lay-out around the taller header.
    var onBodyImageLoaded: (() -> Void)?

    private let bannerHeight: CGFloat = 100
    private let avatarSize: CGFloat = 72

    // MARK: Subviews

    private lazy var bannerImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = .secondarySystemBackground
        return view
    }()

    private lazy var avatarImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = avatarSize / 2
        view.layer.borderWidth = 3
        view.layer.borderColor = UIColor.systemBackground.cgColor
        view.backgroundColor = .tertiarySystemBackground
        view.image = UIImage(systemName: "person.crop.circle.fill")
        view.tintColor = .secondaryLabel
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .title2).pointSize)
        label.adjustsFontForContentSizeCategory = true
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

    private lazy var bioLabel: BodyTextView = {
        let view = BodyTextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tapped = { [weak self] url in
            self?.linkTapped?(url)
        }
        view.onContentSizeChange = { [weak self] in
            self?.onBodyImageLoaded?()
        }
        return view
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
        avatarImageView.layer.borderColor = UIColor.systemBackground.cgColor
    }

    private func setup() {
        backgroundColor = Theme.background

        addSubview(bannerImageView)
        addSubview(avatarImageView)
        addSubview(titleLabel)
        addSubview(handleLabel)
        addSubview(statsLabel)
        addSubview(bioLabel)
        addSubview(separator)

        let margin: CGFloat = 16

        NSLayoutConstraint.activate([
            bannerImageView.topAnchor.constraint(equalTo: topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerImageView.heightAnchor.constraint(equalToConstant: bannerHeight),

            avatarImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            avatarImageView.centerYAnchor.constraint(equalTo: bannerImageView.bottomAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: avatarSize),

            titleLabel.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),

            handleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            handleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            handleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),

            statsLabel.topAnchor.constraint(equalTo: handleLabel.bottomAnchor, constant: 6),
            statsLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            statsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),

            bioLabel.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 12),
            bioLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            bioLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),

            separator.topAnchor.constraint(equalTo: bioLabel.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: Configuration

    func configure(
        title: String,
        handle: String,
        statsText: String,
        bioMarkdown: String?
    ) {
        titleLabel.text = title
        handleLabel.text = handle
        statsLabel.text = statsText
        configureBio(markdown: bioMarkdown)
    }

    private func configureBio(markdown: String?) {
        guard let markdown, !markdown.isEmpty else {
            bioLabel.attributedText = NSAttributedString(string: "")
            bioLabel.isHidden = true
            return
        }
        bioLabel.isHidden = false
        // Set the loader before the body so inline images start loading on assign.
        bioLabel.imageService = imageService
        bioLabel.attributedText = MarkdownRenderer.shared.imageBody(markdown: markdown, textSizeAdjustment: 0)
    }

    // MARK: Images

    func setBannerImage(_ image: UIImage?) {
        bannerImageView.image = image
    }

    func setAvatarImage(_ image: UIImage?) {
        guard let image else { return }
        avatarImageView.image = image
    }
}
