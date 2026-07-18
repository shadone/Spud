//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The post card's top lockup: the community on the left (icon + display name +
/// "c/name@instance" handle) and the post creator on the top-right (avatar +
/// "u/name@instance", ellipsized). The community and creator show and hide as
/// one unit — the parent card toggles the whole header via
/// `options.showCommunityAndCreator`. Only the creator is redactable; the
/// community is the card's public context.
final class ShareCardHeaderView: UIView {
    let communityIcon = ShareCardCommunityIconView(diameter: ShareCardMetrics.communityIconSize)
    /// The redactable creator lockup, exposed so the editor (Task 5) can map a
    /// tap on it to `redactIdentities`.
    let creatorView = ShareCardPersonView(
        avatarSize: ShareCardMetrics.creatorAvatarSize,
        handleFont: ShareCardFonts.creatorHandle
    )

    private let nameLabel = UILabel()
    private let handleLabel = UILabel()

    init() {
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = ShareCardFonts.communityName
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        handleLabel.font = ShareCardFonts.communityHandle
        handleLabel.numberOfLines = 1
        handleLabel.lineBreakMode = .byTruncatingTail
        handleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let nameStack = UIStackView(arrangedSubviews: [nameLabel, handleLabel])
        nameStack.axis = .vertical
        nameStack.spacing = 2
        nameStack.alignment = .leading

        let lockup = UIStackView(arrangedSubviews: [communityIcon, nameStack])
        lockup.axis = .horizontal
        lockup.spacing = 10
        lockup.alignment = .center
        lockup.translatesAutoresizingMaskIntoConstraints = false

        addSubview(lockup)
        addSubview(creatorView)

        let creatorWidth = creatorView.widthAnchor.constraint(lessThanOrEqualToConstant: ShareCardMetrics.creatorMaxWidth)

        NSLayoutConstraint.activate([
            lockup.leadingAnchor.constraint(equalTo: leadingAnchor),
            lockup.topAnchor.constraint(equalTo: topAnchor),
            lockup.bottomAnchor.constraint(equalTo: bottomAnchor),

            creatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            creatorView.topAnchor.constraint(equalTo: topAnchor),
            creatorView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            creatorView.leadingAnchor.constraint(greaterThanOrEqualTo: lockup.trailingAnchor, constant: 12),
            creatorWidth,
        ])
    }

    /// Populates the header from a post summary and applies the palette /
    /// redaction. `post` is required (the header only renders for a `.post`
    /// card or a chain card's post context; a headerless chain never
    /// instantiates this view).
    func configure(post: ShareCardContent.PostSummary, redactIdentities: Bool, palette: ShareCardPalette) {
        communityIcon.configure(name: post.communityName, handle: post.communityHandle)
        communityIcon.setImage(nil)
        nameLabel.text = post.communityName
        nameLabel.textColor = palette.ink
        handleLabel.text = post.communityHandle
        handleLabel.textColor = palette.faint
        creatorView.configure(handle: post.creatorHandle, redacted: redactIdentities, palette: palette)
    }
}
