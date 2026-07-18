//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import UIKit

/// The post card's stats row: a teal score triangle + score and a comment
/// glyph + count on the left, and the absolute timestamp right-aligned.
///
/// Guardrail: the score/comment cluster toggles with `options.showStats`, but
/// the timestamp is NOT part of that toggle — it renders in EVERY
/// configuration. When stats are hidden the row still renders, carrying the
/// timestamp alone, right-aligned. That is why this view is never itself hidden
/// by the card; only its left cluster is.
final class ShareCardStatsView: UIView {
    private let scoreTriangle = UIImageView()
    private let scoreLabel = UILabel()
    private let commentGlyph = UIImageView()
    private let commentLabel = UILabel()
    private let timestampLabel = UILabel()
    private let leftCluster: UIStackView

    init() {
        let scoreGroup = UIStackView()
        let commentGroup = UIStackView()
        leftCluster = UIStackView(arrangedSubviews: [scoreGroup, commentGroup])
        super.init(frame: .zero)
        setUp(scoreGroup: scoreGroup, commentGroup: commentGroup)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp(scoreGroup: UIStackView, commentGroup: UIStackView) {
        translatesAutoresizingMaskIntoConstraints = false

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        scoreTriangle.image = UIImage(systemName: "arrowtriangle.up.fill", withConfiguration: symbolConfig)
        scoreTriangle.contentMode = .scaleAspectFit
        commentGlyph.image = UIImage(systemName: "bubble.left.fill", withConfiguration: symbolConfig)
        commentGlyph.contentMode = .scaleAspectFit

        scoreLabel.font = ShareCardFonts.statValue
        commentLabel.font = ShareCardFonts.statValue

        configure(group: scoreGroup, glyph: scoreTriangle, label: scoreLabel)
        configure(group: commentGroup, glyph: commentGlyph, label: commentLabel)

        leftCluster.axis = .horizontal
        leftCluster.spacing = 16
        leftCluster.alignment = .center
        leftCluster.translatesAutoresizingMaskIntoConstraints = false

        timestampLabel.font = ShareCardFonts.timestamp
        timestampLabel.textAlignment = .right
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(leftCluster)
        addSubview(timestampLabel)

        NSLayoutConstraint.activate([
            leftCluster.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftCluster.topAnchor.constraint(equalTo: topAnchor),
            leftCluster.bottomAnchor.constraint(equalTo: bottomAnchor),
            timestampLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            timestampLabel.centerYAnchor.constraint(equalTo: leftCluster.centerYAnchor),
            timestampLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leftCluster.trailingAnchor, constant: 8),
            timestampLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            timestampLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    private func configure(group: UIStackView, glyph: UIImageView, label: UILabel) {
        glyph.setContentHuggingPriority(.required, for: .horizontal)
        group.axis = .horizontal
        group.spacing = 5
        group.alignment = .center
        group.addArrangedSubview(glyph)
        group.addArrangedSubview(label)
    }

    /// Populates the row. `showStats` toggles only the score/comment cluster;
    /// the timestamp always renders. `locale`/`timeZone` are the timestamp's
    /// determinism seam (see ``ShareCardStyle/timestampString(_:locale:timeZone:)``).
    func configure(
        post: ShareCardContent.PostSummary,
        showStats: Bool,
        palette: ShareCardPalette,
        locale: Locale,
        timeZone: TimeZone
    ) {
        leftCluster.isHidden = !showStats
        scoreTriangle.tintColor = ShareCardPalette.teal
        scoreLabel.text = CountFormatter.string(post.score)
        scoreLabel.textColor = palette.sub
        commentGlyph.tintColor = palette.faint
        commentLabel.text = CountFormatter.string(post.commentCount)
        commentLabel.textColor = palette.sub
        timestampLabel.text = ShareCardStyle.timestampString(post.published, locale: locale, timeZone: timeZone)
        timestampLabel.textColor = palette.faint
    }
}
