//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import UIKit

/// One line of the comment-chain card: a rounded rail on the left and, to its
/// right, the author lockup + score mini-stat, the comment body, and — for the
/// shared comment only — a "SHARED" tag and the comment's own absolute
/// timestamp.
///
/// The destination line (the shared comment) is emphasized per the plan's
/// binding chain spec: a TEAL rail (ancestors get a `hair` rail), a 15.5pt
/// medium full-opacity body (ancestors are 13.5pt at 74% opacity), the "SHARED"
/// tag (9.5pt heavy uppercase teal), and its own timestamp. The author lockup
/// reuses the redactable ``ShareCardPersonView`` — redaction masks every author,
/// exactly as the post card's creator byline.
final class ShareChainRowView: UIView {
    private let rail = UIView()
    private let author = ShareCardPersonView(
        avatarSize: ShareCardMetrics.chainAuthorAvatarSize,
        handleFont: ShareCardFonts.chainAuthorHandle,
        spacing: 5
    )
    private let scoreTriangle = UIImageView()
    private let scoreLabel = UILabel()
    private let sharedTag = UILabel()
    private let bodyLabel = UILabel()
    private let timestampLabel = UILabel()

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

        rail.translatesAutoresizingMaskIntoConstraints = false
        rail.layer.cornerRadius = ShareCardMetrics.chainRailWidth / 2
        rail.layer.cornerCurve = .continuous
        addSubview(rail)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        scoreTriangle.image = UIImage(systemName: "arrowtriangle.up.fill", withConfiguration: symbolConfig)
        scoreTriangle.contentMode = .scaleAspectFit
        scoreTriangle.setContentHuggingPriority(.required, for: .horizontal)
        scoreLabel.font = ShareCardFonts.chainScore

        let scoreStat = UIStackView(arrangedSubviews: [scoreTriangle, scoreLabel])
        scoreStat.axis = .horizontal
        scoreStat.spacing = 4
        scoreStat.alignment = .center
        scoreStat.setContentHuggingPriority(.required, for: .horizontal)
        scoreStat.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Author on the left, score mini-stat pinned to the right.
        let headerRow = UIStackView(arrangedSubviews: [author, scoreStat])
        headerRow.axis = .horizontal
        headerRow.spacing = 8
        headerRow.alignment = .center

        sharedTag.font = ShareCardFonts.chainSharedTag

        bodyLabel.numberOfLines = 0

        timestampLabel.font = ShareCardFonts.chainTimestamp

        let column = configuredColumn(headerRow: headerRow)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            rail.leadingAnchor.constraint(equalTo: leadingAnchor),
            rail.topAnchor.constraint(equalTo: column.topAnchor),
            rail.bottomAnchor.constraint(equalTo: column.bottomAnchor),
            rail.widthAnchor.constraint(equalToConstant: ShareCardMetrics.chainRailWidth),

            column.leadingAnchor.constraint(equalTo: rail.trailingAnchor, constant: 11),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func configuredColumn(headerRow: UIStackView) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: [sharedTag, headerRow, bodyLabel, timestampLabel])
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .fill
        return stack
    }

    /// Populates the line from a chain item.
    ///
    /// - Parameters:
    ///   - item: the ancestor or shared comment to render.
    ///   - redactIdentities: masks the author lockup when set.
    ///   - locale/timeZone: the destination timestamp's determinism seam,
    ///     mirroring ``ShareCardView`` (production `.current`; snapshots pin
    ///     `en_US_POSIX`/`GMT`).
    func configure(
        item: ShareCardContent.ChainItem,
        redactIdentities: Bool,
        palette: ShareCardPalette,
        locale: Locale,
        timeZone: TimeZone
    ) {
        let isDestination = item.isDestination
        rail.backgroundColor = isDestination ? ShareCardPalette.teal : palette.hair

        author.configure(handle: item.authorHandle, redacted: redactIdentities, palette: palette)

        scoreTriangle.tintColor = ShareCardPalette.teal
        scoreLabel.text = CountFormatter.string(item.score)
        scoreLabel.textColor = palette.sub

        // "SHARED" tag: destination only, with a touch of tracking for a
        // tag-like read.
        sharedTag.isHidden = !isDestination
        if isDestination {
            sharedTag.attributedText = NSAttributedString(
                string: "SHARED",
                attributes: [
                    .font: ShareCardFonts.chainSharedTag,
                    .foregroundColor: ShareCardPalette.teal,
                    .kern: 0.8,
                ]
            )
        }

        applyBody(item: item, isDestination: isDestination, palette: palette)

        // The shared comment carries its own absolute timestamp; ancestors do
        // not. The timestamp is a guardrail element on the destination — it
        // renders even when identities are redacted.
        if isDestination, let published = item.published {
            timestampLabel.isHidden = false
            timestampLabel.text = ShareCardStyle.timestampString(published, locale: locale, timeZone: timeZone)
            timestampLabel.textColor = palette.faint
        } else {
            timestampLabel.isHidden = true
        }
    }

    private func applyBody(item: ShareCardContent.ChainItem, isDestination: Bool, palette: ShareCardPalette) {
        guard let body = item.bodyPlain, !body.isEmpty else {
            bodyLabel.isHidden = true
            return
        }
        bodyLabel.isHidden = false
        let font = isDestination ? ShareCardFonts.chainDestinationBody : ShareCardFonts.chainAncestorBody
        let color = isDestination ? palette.ink : palette.ink.withAlphaComponent(0.74)
        bodyLabel.attributedText = NSAttributedString(
            string: body,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: ShareCardStyle.paragraphStyle(lineHeightMultiple: 1.32),
            ]
        )
    }
}
