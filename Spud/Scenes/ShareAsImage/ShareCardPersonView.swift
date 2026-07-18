//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A person lockup for the share card: an avatar circle plus a monospaced
/// "u/name@instance" handle. This is THE redactable identity view — when
/// `redacted` is set, the avatar becomes a striped placeholder circle and the
/// handle becomes "u/•••••••", exactly as the card's `redactIdentities` option
/// requires. Reused for the post card's creator byline AND (Task 3) every
/// author line in a comment chain, so it lives in its own file with a
/// configurable avatar size and handle font.
///
/// A person is the ONLY redactable element; the community is never redacted
/// (see ``ShareCardCommunityIconView``).
final class ShareCardPersonView: UIView {
    private let avatar: PersonAvatarCircle
    private let handleLabel = UILabel()

    /// The redacted handle placeholder — seven bullets, matching the deck.
    private static let redactedHandle = "u/" + String(repeating: "\u{2022}", count: 7)

    init(avatarSize: CGFloat, handleFont: UIFont, spacing: CGFloat = 6) {
        avatar = PersonAvatarCircle(diameter: avatarSize)
        super.init(frame: .zero)
        setUp(handleFont: handleFont, spacing: spacing)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp(handleFont: UIFont, spacing: CGFloat) {
        translatesAutoresizingMaskIntoConstraints = false

        handleLabel.translatesAutoresizingMaskIntoConstraints = false
        handleLabel.font = handleFont
        handleLabel.lineBreakMode = .byTruncatingTail
        handleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(avatar)
        addSubview(handleLabel)

        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: leadingAnchor),
            avatar.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatar.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            avatar.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            handleLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: spacing),
            handleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            handleLabel.topAnchor.constraint(equalTo: topAnchor),
            handleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Configures the lockup. When `redacted` the identity is masked regardless
    /// of `handle`. When NOT redacted and `handle` is `nil` (e.g. a deleted
    /// account) the whole view hides, so the caller's layout collapses around
    /// it.
    func configure(handle: String?, redacted: Bool, palette: ShareCardPalette) {
        avatar.configure(redacted: redacted, palette: palette)

        if redacted {
            isHidden = false
            handleLabel.text = Self.redactedHandle
            handleLabel.textColor = palette.faint
        } else if let handle {
            isHidden = false
            handleLabel.text = handle
            handleLabel.textColor = palette.sub
        } else {
            isHidden = true
        }
    }
}

/// The avatar circle inside a ``ShareCardPersonView``. Because the card content
/// carries no per-person avatar image, the non-redacted state is a neutral
/// placeholder (a `chip`-filled circle with a `person.fill` glyph); the
/// redacted state is a striped circle. Both are drawn deterministically (no
/// `UIVisualEffectView`) so the off-screen render is byte-stable.
private final class PersonAvatarCircle: UIView {
    private let diameter: CGFloat
    private let glyphView = UIImageView()
    private var isRedacted = false
    private var stripeColor: UIColor = .clear
    private var fillColor: UIColor = .clear

    init(diameter: CGFloat) {
        self.diameter = diameter
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false

        glyphView.translatesAutoresizingMaskIntoConstraints = false
        glyphView.contentMode = .scaleAspectFit
        glyphView.image = UIImage(systemName: "person.fill")
        addSubview(glyphView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
            glyphView.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyphView.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyphView.widthAnchor.constraint(equalToConstant: diameter * 0.56),
            glyphView.heightAnchor.constraint(equalToConstant: diameter * 0.56),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(redacted: Bool, palette: ShareCardPalette) {
        isRedacted = redacted
        glyphView.isHidden = redacted
        glyphView.tintColor = palette.faint
        fillColor = redacted ? palette.hair : palette.chip
        stripeColor = palette.faint
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let circle = UIBezierPath(ovalIn: bounds)
        context.saveGState()
        circle.addClip()

        fillColor.setFill()
        context.fill(bounds)

        if isRedacted {
            // Diagonal hatch stripes over the fill for the "redacted" look.
            stripeColor.setStroke()
            let path = UIBezierPath()
            path.lineWidth = 1.5
            let spacing: CGFloat = 5
            var x = -bounds.height
            while x < bounds.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + bounds.height, y: bounds.height))
                x += spacing
            }
            path.stroke()
        }

        context.restoreGState()
    }
}
