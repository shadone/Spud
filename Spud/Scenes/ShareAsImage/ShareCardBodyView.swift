//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The post card's body block. Renders the plain-text body preview in one of
/// the three treatments:
///
/// - `.full` — the whole body, unclamped.
/// - `.truncate` — clamped to a fixed max height with a bottom fade to the
///   panel color and a teal "Read the full post on Lemmy" line, but ONLY when
///   the body actually overflows that height (a short body renders in full with
///   no fade, so the treatment never fades real text into nothing).
/// - `.titleOnly` — nothing (the parent hides this view).
///
/// The overflow decision is made at configure time against the card's FIXED
/// content width (the card is a constant-width artifact), so it is
/// deterministic and needs no post-layout re-measure.
final class ShareCardBodyView: UIView {
    private let clipView = FadeClipView()
    private let bodyLabel = UILabel()
    private let readMoreLabel = UILabel()

    private var bottomPin: NSLayoutConstraint!
    private var heightCap: NSLayoutConstraint!

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

        bodyLabel.numberOfLines = 0
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        clipView.addSubview(bodyLabel)

        readMoreLabel.font = ShareCardFonts.readMore
        readMoreLabel.text = "Read the full post on Lemmy \u{2192}"

        let stack = UIStackView(arrangedSubviews: [clipView, readMoreLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        bottomPin = bodyLabel.bottomAnchor.constraint(equalTo: clipView.bottomAnchor)
        heightCap = clipView.heightAnchor.constraint(equalToConstant: ShareCardMetrics.truncatedBodyMaxHeight)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            bodyLabel.topAnchor.constraint(equalTo: clipView.topAnchor),
            bodyLabel.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            bottomPin,
        ])
    }

    /// Configures the body. Returns `false` when there is nothing to show
    /// (`bodyPlain` empty/`nil` or `treatment == .titleOnly`), so the parent
    /// can hide the view.
    @discardableResult
    func configure(
        bodyPlain: String?,
        treatment: ShareCardOptions.BodyTreatment,
        palette: ShareCardPalette
    ) -> Bool {
        guard treatment != .titleOnly, let bodyPlain, !bodyPlain.isEmpty else {
            return false
        }

        let paragraph = ShareCardStyle.paragraphStyle(lineHeightMultiple: 1.58)
        let attributed = NSAttributedString(
            string: bodyPlain,
            attributes: [
                .font: ShareCardFonts.body,
                .foregroundColor: palette.ink.withAlphaComponent(0.9),
                .paragraphStyle: paragraph,
            ]
        )
        bodyLabel.attributedText = attributed

        let neededHeight = attributed.boundingRect(
            with: CGSize(width: ShareCardMetrics.contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height
        let overflows = treatment == .truncate && neededHeight > ShareCardMetrics.truncatedBodyMaxHeight

        if overflows {
            bottomPin.isActive = false
            heightCap.isActive = true
            clipView.setFade(color: palette.panel, height: ShareCardMetrics.bodyFadeHeight)
            readMoreLabel.isHidden = false
            readMoreLabel.textColor = ShareCardPalette.teal
        } else {
            heightCap.isActive = false
            bottomPin.isActive = true
            clipView.setFade(color: nil, height: 0)
            readMoreLabel.isHidden = true
        }
        return true
    }
}

/// A clipping container that fades its bottom edge to a solid color via a
/// `CAGradientLayer` — the truncated-body bottom fade. Uses a plain layer (no
/// `UIVisualEffectView`) so it renders identically off-screen.
private final class FadeClipView: UIView {
    private let fadeLayer = CAGradientLayer()
    private var fadeHeight: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        fadeLayer.startPoint = CGPoint(x: 0.5, y: 0)
        fadeLayer.endPoint = CGPoint(x: 0.5, y: 1)
        fadeLayer.isHidden = true
        layer.addSublayer(fadeLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Enables the bottom fade to `color` (or disables it when `color` is nil).
    func setFade(color: UIColor?, height: CGFloat) {
        fadeHeight = height
        if let color {
            fadeLayer.colors = [color.withAlphaComponent(0).cgColor, color.cgColor]
            fadeLayer.isHidden = false
        } else {
            fadeLayer.isHidden = true
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fadeLayer.frame = CGRect(
            x: 0,
            y: bounds.height - fadeHeight,
            width: bounds.width,
            height: fadeHeight
        )
    }
}
