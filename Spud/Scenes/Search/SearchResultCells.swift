//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUtilKit
import UIKit

// MARK: - Post result cell

/// Post search result, rendered through the SHARED `PostListPostContentView` — the
/// exact view the feed cell hosts — so a searched post shows the same rich info as the
/// feed (community@instance, counts, thumbnail, status/author badges, NSFW blur), plus
/// an author line under the title. The trailing vote arrows are suppressed (a search
/// row taps through to PostDetail, it doesn't vote).
///
/// Like `ActivityPostRowCell`, this hosts a plain content `UIView`, not a nested
/// `UITableViewCell` — a nested cell's own `contentView` is attached by autoresizing
/// mask, which severs the Auto Layout height chain and collapses the embedded content.
/// The view controller configures the exposed `postContentView` (view model + media /
/// reveal callbacks) the way `ActivityViewController` / `PersonViewController` do.
final class SearchPostCell: UITableViewCell {
    static let reuseIdentifier = "SearchPostCell"

    /// The reused feed post rendering. Exposed so the view controller configures its
    /// view model and callbacks directly, mirroring `PersonViewController.makePostCell`.
    let postContentView = PostListPostContentView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        // No disclosure chevron and no selection tint: the cell renders as a feed post
        // (which carries neither) and taps through to PostDetail via `didSelectRow`.
        selectionStyle = .none

        postContentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(postContentView)

        NSLayoutConstraint.activate([
            postContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            postContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            postContentView.topAnchor.constraint(equalTo: contentView.topAnchor),
            postContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Reset the shared rendering (cancels its thumbnail load and clears callbacks).
        postContentView.prepareForReuse()
    }
}

// MARK: - Community result cell

/// Community search result: icon + name + subscriber count, with an inline
/// subscribe toggle that calls back to the view controller.
final class SearchCommunityCell: UITableViewCell {
    static let reuseIdentifier = "SearchCommunityCell"

    /// Invoked when the subscribe button is tapped. Argument is the desired
    /// subscribed state (`true` = subscribe, `false` = unsubscribe).
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

    /// Marks a community that is "meta" for its own instance (e.g. an
    /// announcements / site community) — same glyph as the SwiftUI
    /// `MetaCommunityBadge` (Discover / Communities tab) for visual
    /// consistency. Hidden by default; `configure(with:imageService:)` shows
    /// it when `MetaCommunityClassifier` calls the result meta.
    ///
    /// This cell doesn't compose its own `accessibilityLabel` (default subview
    /// aggregation applies), so the badge is made its own accessibility
    /// element carrying the "Instance community" marker — VoiceOver announces
    /// it alongside the name only when it's visible.
    private let metaBadge: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "building.2.fill"))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .secondaryLabel
        view.contentMode = .scaleAspectFit
        view.isHidden = true
        view.isAccessibilityElement = true
        view.accessibilityLabel = NSLocalizedString(
            "Instance community", comment: "Meta community badge"
        )
        return view
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

    /// The last state rendered via `applySubscribedState`. Drives the tap toggle
    /// intent: subscribe when the current state isn't already subscribed-ish
    /// (subscribed / pending / approvalRequired), unsubscribe otherwise.
    private var currentState: CommunitySubscribedState = .notSubscribed
    private var iconLoadTask: Task<Void, Never>?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        // Name + meta badge + a flexible trailing spacer, so the badge sits right
        // after the name instead of being pushed to the row's far edge.
        let nameRow = UIStackView(arrangedSubviews: [nameLabel, metaBadge, UIView()])
        nameRow.translatesAutoresizingMaskIntoConstraints = false
        nameRow.axis = .horizontal
        nameRow.spacing = 6
        nameRow.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [nameRow, detailLabel])
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

            metaBadge.widthAnchor.constraint(equalToConstant: 16),
            metaBadge.heightAnchor.constraint(equalToConstant: 16),

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

    /// Configures the icon + text. Does NOT touch the subscribe button — the
    /// resolved 5-state (persisted-DB-wins, network fallback) is owned by
    /// `SearchViewModel.subscribeState(for:)` and applied separately via
    /// `applySubscribedState(_:)` (see `SearchViewController`'s cell provider),
    /// so a result's stale network `followState` can never overwrite a live,
    /// more-accurate persisted state (e.g. Pending) painted after `configure`.
    func configure(with result: SearchCommunityResult, imageService: ImageServiceType) {
        nameLabel.text = result.qualifiedName
        detailLabel.text = "\(result.subscribersText) subscribers"

        // Real fields on `SearchCommunityResult` (bare `name` + the home
        // `InstanceActorId`), not a `qualifiedName` string split — the result
        // already carries both separately.
        metaBadge.isHidden = !MetaCommunityClassifier.classify(
            name: result.name, title: nil, instanceHost: result.instance.hostWithPort, siteName: nil
        ).isMeta

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

    /// Updates the button's title/icon/style to the real 5-state
    /// ``CommunitySubscribedState`` (Subscribe / Subscribed / Pending / Requested),
    /// via the shared `CommunitySubscribeButtonLabel` also used by
    /// `CommunityHeaderView`'s community-detail button — so the two surfaces never
    /// show different copy for the same state. Called on configure (the VC-resolved
    /// state), optimistically right after a tap, and again when the live DB
    /// observation reconciles to the server's confirmed answer.
    func applySubscribedState(_ state: CommunitySubscribedState) {
        currentState = state
        subscribeButton.configuration?.title = CommunitySubscribeButtonLabel.title(for: state)
        subscribeButton.configuration?.image = UIImage(systemName: CommunitySubscribeButtonLabel.symbol(for: state))
        subscribeButton.configuration?.baseForegroundColor = state.isSubscribed ? .secondaryLabel : nil
    }

    @objc
    private func didTapSubscribe() {
        subscribeTapped?(!currentState.isSubscribed)
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
///
/// The rendering is the shared `SearchCommentContentView` (also hosted by the
/// Activity timeline's comment row), pinned to the cell's content layout-margins
/// guide so the inset matches the other search cells.
final class SearchCommentCell: UITableViewCell {
    static let reuseIdentifier = "SearchCommentCell"

    private let commentContentView = SearchCommentContentView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        commentContentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(commentContentView)

        NSLayoutConstraint.activate([
            commentContentView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            commentContentView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            commentContentView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            commentContentView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with result: SearchCommentResult) {
        commentContentView.configure(
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
}
