//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The share card's footer: a hairline top border, the permalink on the left,
/// and the "via [glyph] Spud" wordmark on the right.
///
/// Guardrail: the permalink ALWAYS renders and is NOT toggleable — a shared
/// card must always point back to the real post/comment so it can never be
/// mistaken for original, unattributed content. Only the "via Spud" wordmark
/// toggles (`options.showViaSpudMark`). The permalink is middle-truncated so a
/// long URL still shows both its host and its trailing id.
///
/// Reused verbatim by Task 3's comment-chain card (with the shared comment's
/// permalink), which is why it lives in its own file.
final class ShareCardFooterView: UIView {
    private let topBorder = UIView()
    /// The always-present permalink label. Exposed so the editor can read its
    /// frame; it is never a tap target (the permalink cannot be toggled).
    let permalinkLabel = UILabel()
    private let viaLabel = UILabel()
    private let glyph = UIView()
    private let wordmark = UILabel()
    private let viaStack: UIStackView

    init() {
        viaStack = UIStackView(arrangedSubviews: [viaLabel, glyph, wordmark])
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        topBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBorder)

        permalinkLabel.font = ShareCardFonts.permalink
        permalinkLabel.numberOfLines = 1
        permalinkLabel.lineBreakMode = .byTruncatingMiddle
        permalinkLabel.translatesAutoresizingMaskIntoConstraints = false
        permalinkLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(permalinkLabel)

        viaLabel.text = "via"
        viaLabel.font = ShareCardFonts.viaLabel

        // The card's only footer brand mark: a fixed teal rounded-square token
        // (the app has no bundled wordmark asset), drawn deterministically.
        glyph.translatesAutoresizingMaskIntoConstraints = false
        glyph.backgroundColor = ShareCardPalette.teal
        glyph.layer.cornerRadius = 4
        glyph.layer.cornerCurve = .continuous

        wordmark.text = "Spud"
        wordmark.font = ShareCardFonts.viaWordmark

        viaStack.axis = .horizontal
        viaStack.spacing = 5
        viaStack.alignment = .center
        viaStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(viaStack)

        let permalinkTrailing = permalinkLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: viaStack.leadingAnchor,
            constant: -10
        )
        permalinkTrailing.priority = .defaultHigh

        NSLayoutConstraint.activate([
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: ShareCardMetrics.hairline),

            glyph.widthAnchor.constraint(equalToConstant: 14),
            glyph.heightAnchor.constraint(equalToConstant: 14),

            permalinkLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            permalinkLabel.topAnchor.constraint(equalTo: topBorder.bottomAnchor, constant: 14),
            permalinkLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            permalinkLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            permalinkTrailing,

            viaStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            viaStack.centerYAnchor.constraint(equalTo: permalinkLabel.centerYAnchor),
            viaStack.topAnchor.constraint(greaterThanOrEqualTo: topBorder.bottomAnchor, constant: 14),
            viaStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    /// Populates the footer. `permalink.absoluteString` is shown verbatim
    /// (middle-truncated); `showViaSpudMark` toggles only the wordmark.
    func configure(permalink: URL, showViaSpudMark: Bool, palette: ShareCardPalette) {
        topBorder.backgroundColor = palette.hair
        permalinkLabel.text = permalink.absoluteString
        permalinkLabel.textColor = palette.faint
        viaLabel.textColor = palette.faint
        wordmark.textColor = palette.ink
        viaStack.isHidden = !showViaSpudMark
    }
}
