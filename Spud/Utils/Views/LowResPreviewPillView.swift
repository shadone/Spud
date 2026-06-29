//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A small, non-blocking "you're seeing a low-resolution preview" pill.
///
/// Shown over an image whenever the cached thumbnail is on screen but the
/// full-resolution asset couldn't load (slow network or offline). Rather than
/// covering the image with the hard failure plate, this stays out of the way: a
/// frosted, dark-material rounded pill with a glyph and a short label, sized to
/// its content.
///
/// Two surfaces use it, configured differently at construction:
///   - the post-detail header overlays an *interactive* pill ("Low-res preview ·
///     tap to retry") whose tap re-requests the full image and whose context
///     menu / long-press reaches Open in browser;
///   - the full-screen media viewer shows an *informational* pill ("Showing
///     low-resolution preview") in its auto-hiding chrome.
///
/// Built on `UIVisualEffectView` so it reads over any image. Because the blur
/// only renders when drawn through the key window, snapshot tests that capture
/// it must use the `drawHierarchyInKeyWindow:` strategy.
final class LowResPreviewPillView: UIView {
    /// Invoked when the pill is tapped. `nil` makes the pill informational (no
    /// tap, no `.button` trait) — the media-viewer presentation.
    var onTap: (() -> Void)?

    private let blurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()

    private let glyphView: UIImageView = {
        let imageView = UIImageView(image: UIImage(
            systemName: "rectangle.dashed",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        ))
        imageView.tintColor = UIColor.white.withAlphaComponent(0.85)
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: .systemFont(ofSize: 13, weight: .medium))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor.white.withAlphaComponent(0.9)
        label.numberOfLines = 1
        return label
    }()

    /// - Parameters:
    ///   - title: the pill's label text.
    ///   - showsRetryHint: appends a tappable chevron (`arrow.clockwise`) so an
    ///     interactive pill reads as "tap to retry". Pass `false` for the
    ///     informational viewer pill.
    init(title: String, showsRetryHint: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title

        var arranged: [UIView] = [glyphView, titleLabel]
        if showsRetryHint {
            let retryGlyph = UIImageView(image: UIImage(
                systemName: "arrow.clockwise",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            ))
            retryGlyph.tintColor = UIColor.white.withAlphaComponent(0.85)
            retryGlyph.contentMode = .scaleAspectFit
            retryGlyph.setContentHuggingPriority(.required, for: .horizontal)
            arranged.append(retryGlyph)
        }

        let stack = UIStackView(arrangedSubviews: arranged)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        // The stack is laid out by the pill; the pill's tap gesture handles touches.
        stack.isUserInteractionEnabled = false

        addSubview(blurView)
        blurView.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 11),
            stack.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -11),
            stack.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -6),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        isAccessibilityElement = true
        accessibilityLabel = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Configures the accessibility traits and hint for the active mode. Called
    /// by the owner once it has decided whether the pill is interactive.
    func configureAccessibility(isInteractive: Bool, hint: String?) {
        accessibilityTraits = isInteractive ? .button : .staticText
        accessibilityHint = hint
    }

    @objc
    private func handleTap() {
        onTap?()
    }
}
