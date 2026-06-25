//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A tap-to-reveal blur layer placed over NSFW media. Add it as a subview
/// pinned to the host image view's edges. While not revealed it covers the
/// image with a blur material and an "eye.slash" hint; tapping calls
/// ``onReveal``. Reveal state is owned by the host (session-only), so the host
/// calls ``setRevealed(_:)`` on configure and reuse.
final class NsfwBlurOverlayView: UIView {
    /// Called when the user taps the overlay to reveal the media.
    var onReveal: (() -> Void)?

    /// Whether a caption ("Tap to reveal") is shown. Off for tight thumbnails.
    var showsCaption: Bool {
        get { !captionLabel.isHidden }
        set { captionLabel.isHidden = !newValue }
    }

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))

    private lazy var glyphView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        let view = UIImageView(image: UIImage(systemName: "eye.slash.fill", withConfiguration: config))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .secondaryLabel
        return view
    }()

    private lazy var captionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString("Tap to reveal", comment: "NSFW blur overlay hint")
        label.font = .preferredFont(forTextStyle: .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        return label
    }()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        let stack = UIStackView(arrangedSubviews: [glyphView, captionLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        addSubview(stack)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))

        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString("NSFW content, hidden", comment: "NSFW blur overlay accessibility label")
        accessibilityTraits = .button
        accessibilityHint = NSLocalizedString("Double tap to reveal", comment: "NSFW blur overlay accessibility hint")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func didTap() {
        onReveal?()
    }

    /// Shows or hides the overlay. When revealed the overlay is hidden and
    /// pass-through (so taps reach the underlying media).
    func setRevealed(_ revealed: Bool) {
        isHidden = revealed
    }
}
