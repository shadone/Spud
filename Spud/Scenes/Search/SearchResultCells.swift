//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import UIKit

// MARK: - Post result cell

/// Post search result, styled like a feed cell: bold title above a secondary
/// "community  score  comments" line, with an optional thumbnail.
final class SearchPostCell: UITableViewCell {
    static let reuseIdentifier = "SearchPostCell"

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 3
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let thumbnailView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 8
        view.backgroundColor = .secondarySystemBackground
        return view
    }()

    private var thumbnailLoadTask: Task<Void, Never>?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 4

        contentView.addSubview(textStack)
        contentView.addSubview(thumbnailView)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            textStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),

            thumbnailView.leadingAnchor.constraint(equalTo: textStack.trailingAnchor, constant: 12),
            thumbnailView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 56),
            thumbnailView.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailLoadTask?.cancel()
        thumbnailLoadTask = nil
        thumbnailView.image = nil
        thumbnailView.isHidden = false
    }

    func configure(with result: SearchPostResult, imageService: ImageServiceType) {
        titleLabel.text = result.title

        let pieces = [
            result.communityName,
            "\(result.score) points",
            "\(result.numberOfComments) comments",
        ]
        subtitleLabel.text = pieces.joined(separator: "  •  ")

        thumbnailLoadTask?.cancel()
        guard let thumbnailUrl = result.thumbnailUrl else {
            thumbnailView.isHidden = true
            return
        }
        thumbnailView.isHidden = false
        thumbnailLoadTask = Task { [weak self] in
            for await state in imageService.fetch(thumbnailUrl) {
                if Task.isCancelled { return }
                guard let self else { return }
                if case let .ready(image) = state {
                    thumbnailView.image = image
                }
            }
        }
    }
}

// MARK: - Community result cell

/// Community search result: icon + name + subscriber count, with an inline
/// subscribe toggle that calls back to the view controller.
final class SearchCommunityCell: UITableViewCell {
    static let reuseIdentifier = "SearchCommunityCell"

    /// Invoked when the subscribe button is tapped. Argument is the desired
    /// subscribed state.
    var subscribeTapped: ((Bool) -> Void)?

    private let iconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 20
        view.backgroundColor = .secondarySystemBackground
        view.image = UIImage(systemName: "person.3.fill")
        view.tintColor = .tertiaryLabel
        return view
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private lazy var subscribeButton: UIButton = {
        var config = UIButton.Configuration.bordered()
        config.cornerStyle = .capsule
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addTarget(self, action: #selector(didTapSubscribe), for: .touchUpInside)
        return button
    }()

    private var isSubscribed = false
    private var iconLoadTask: Task<Void, Never>?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let textStack = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2

        contentView.addSubview(iconView)
        contentView.addSubview(textStack)
        contentView.addSubview(subscribeButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),

            subscribeButton.leadingAnchor.constraint(equalTo: textStack.trailingAnchor, constant: 12),
            subscribeButton.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            subscribeButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconLoadTask?.cancel()
        iconLoadTask = nil
        iconView.image = UIImage(systemName: "person.3.fill")
        subscribeTapped = nil
    }

    func configure(with result: SearchCommunityResult, imageService: ImageServiceType) {
        nameLabel.text = result.qualifiedName
        detailLabel.text = "\(result.subscribersText) subscribers"
        applySubscribedState(result.isSubscribed)

        iconLoadTask?.cancel()
        guard let iconUrl = result.iconUrl else { return }
        iconLoadTask = Task { [weak self] in
            for await state in imageService.fetch(iconUrl) {
                if Task.isCancelled { return }
                guard let self else { return }
                if case let .ready(image) = state {
                    iconView.image = image
                }
            }
        }
    }

    /// Updates the button's title/style. Called both on configure and
    /// optimistically by the view controller after a tap.
    func applySubscribedState(_ subscribed: Bool) {
        isSubscribed = subscribed
        subscribeButton.configuration?.title = subscribed
            ? NSLocalizedString("Subscribed", comment: "Search community row: already-subscribed button title")
            : NSLocalizedString("Subscribe", comment: "Search community row: subscribe button title")
        subscribeButton.configuration?.baseForegroundColor = subscribed ? .secondaryLabel : nil
    }

    @objc
    private func didTapSubscribe() {
        subscribeTapped?(!isSubscribed)
    }
}

// MARK: - User result cell

/// User search result: avatar + display name + handle.
final class SearchUserCell: UITableViewCell {
    static let reuseIdentifier = "SearchUserCell"

    private let avatarView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 20
        view.backgroundColor = .secondarySystemBackground
        view.image = UIImage(systemName: "person.crop.circle.fill")
        view.tintColor = .tertiaryLabel
        return view
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let handleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private var avatarLoadTask: Task<Void, Never>?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        let textStack = UIStackView(arrangedSubviews: [nameLabel, handleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2

        contentView.addSubview(avatarView)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),

            textStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        avatarView.image = UIImage(systemName: "person.crop.circle.fill")
    }

    func configure(with result: SearchUserResult, imageService: ImageServiceType) {
        nameLabel.text = result.name
        handleLabel.text = result.qualifiedName

        avatarLoadTask?.cancel()
        guard let avatarUrl = result.avatarUrl else { return }
        avatarLoadTask = Task { [weak self] in
            for await state in imageService.fetch(avatarUrl) {
                if Task.isCancelled { return }
                guard let self else { return }
                if case let .ready(image) = state {
                    avatarView.image = image
                }
            }
        }
    }
}

// MARK: - Comment result cell

/// Comment search result: the comment body above its post-title context.
final class SearchCommentCell: UITableViewCell {
    static let reuseIdentifier = "SearchCommentCell"

    private let contentLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 3
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let contextLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        let textStack = UIStackView(arrangedSubviews: [contentLabel, contextLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 4

        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            textStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with result: SearchCommentResult) {
        configure(
            content: result.content,
            context: String(
                format: NSLocalizedString(
                    "%@ on \"%@\"",
                    comment: "Search comment row context: <author> on \"<post title>\""
                ),
                result.creatorName,
                result.postTitle
            )
        )
    }

    /// Renders a comment body above an arbitrary context line. The
    /// `SearchCommentResult` overload builds its `<author> on "<post>"` context on
    /// top of this; other callers (e.g. the Activity timeline) supply their own
    /// context, so the cell is reused rather than forked.
    func configure(content: String, context: String) {
        contentLabel.text = content
        contextLabel.text = context
    }
}
