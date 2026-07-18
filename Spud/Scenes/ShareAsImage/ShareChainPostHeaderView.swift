//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The comment-chain card's optional post-context header: a compact community
/// lockup (26pt icon + display name + "c/name@instance" handle) above the post
/// title (16.5pt heavy), closed off by a hairline. It is context only — there
/// is no creator byline (that belongs on the shared comment, not the post) and
/// nothing here is redactable (the community is always public context; see
/// ``ShareCardCommunityIconView``).
///
/// Distinct from the post card's ``ShareCardHeaderView`` (which carries a 34pt
/// icon plus a creator lockup) — the chain header is deliberately smaller and
/// title-forward, so it reads as background for the comment thread below it.
/// The parent gates it on `includePostInChain` AND a non-nil post summary.
final class ShareChainPostHeaderView: UIView {
    private let communityIcon = ShareCardCommunityIconView(diameter: ShareCardMetrics.chainPostHeaderIconSize)
    private let nameLabel = UILabel()
    private let handleLabel = UILabel()
    private let titleLabel = UILabel()
    private let bottomBorder = UIView()

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

        titleLabel.font = ShareCardFonts.postHeaderTitle
        titleLabel.numberOfLines = 0

        let nameStack = UIStackView(arrangedSubviews: [nameLabel, handleLabel])
        nameStack.axis = .vertical
        nameStack.spacing = 2
        nameStack.alignment = .leading

        let lockup = UIStackView(arrangedSubviews: [communityIcon, nameStack])
        lockup.axis = .horizontal
        lockup.spacing = 8
        lockup.alignment = .center

        let stack = UIStackView(arrangedSubviews: [lockup, titleLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        bottomBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomBorder)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),

            bottomBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBorder.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 16),
            bottomBorder.heightAnchor.constraint(equalToConstant: ShareCardMetrics.hairline),
            bottomBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Populates the header from the chain card's post-context summary and
    /// applies the palette. The icon always renders its deterministic fallback
    /// tile (chain content carries no community icon URL today).
    func configure(post: ShareCardContent.PostSummary, palette: ShareCardPalette) {
        communityIcon.configure(name: post.communityName, handle: post.communityHandle)
        communityIcon.setImage(nil)
        nameLabel.text = post.communityName
        nameLabel.textColor = palette.ink
        handleLabel.text = post.communityHandle
        handleLabel.textColor = palette.faint
        titleLabel.attributedText = NSAttributedString(
            string: post.title,
            attributes: [
                .font: ShareCardFonts.postHeaderTitle,
                .foregroundColor: palette.ink,
                .paragraphStyle: ShareCardStyle.paragraphStyle(lineHeightMultiple: 1.16),
            ]
        )
        bottomBorder.backgroundColor = palette.hair
    }
}
