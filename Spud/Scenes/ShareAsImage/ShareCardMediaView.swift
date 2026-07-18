//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// The post card's media block: a rounded image that scales-to-fill a
/// fixed-height frame, plus its two non-image states — a loading placeholder
/// (chip fill + shimmer + "Loading media…") and an NSFW spoiler (a
/// Core-Image-blurred image behind a dark overlay with an eye glyph and
/// "Sensitive content").
///
/// The spoiler uses a real `CIGaussianBlur` baked into a `UIImage`, NOT a
/// `UIVisualEffectView` — the card must render deterministically off-screen,
/// where live blur effects render as nothing. The shimmer's static (model)
/// state is a flat `chip` fill: the moving highlight lives in an animation,
/// which an off-screen render never captures, so a snapshot of the loading
/// state is a deterministic first frame.
final class ShareCardMediaView: UIView {
    private let imageView = UIImageView()
    private let loadingContainer = UIView()
    private let shimmerHighlight = CAGradientLayer()
    private let loadingCaption = UILabel()
    private let spoilerOverlay = UIView()
    private let eyeGlyph = UIImageView()
    private let sensitiveLabel = UILabel()

    private var heightConstraint: NSLayoutConstraint!
    private var originalImage: UIImage?
    private var isNsfw = false
    private var nsfwRevealed = false

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
        layer.cornerRadius = ShareCardMetrics.mediaCornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true

        heightConstraint = heightAnchor.constraint(
            equalToConstant: ShareCardMetrics.mediaHeightRatio * ShareCardMetrics.contentWidth
        )
        heightConstraint.isActive = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        pinFilling(imageView)

        loadingCaption.text = "Loading media\u{2026}"
        loadingCaption.font = ShareCardFonts.mediaCaption
        loadingCaption.textAlignment = .center
        loadingCaption.translatesAutoresizingMaskIntoConstraints = false
        loadingContainer.addSubview(loadingCaption)
        loadingContainer.layer.addSublayer(shimmerHighlight)
        pinFilling(loadingContainer)
        NSLayoutConstraint.activate([
            loadingCaption.centerXAnchor.constraint(equalTo: loadingContainer.centerXAnchor),
            loadingCaption.centerYAnchor.constraint(equalTo: loadingContainer.centerYAnchor),
        ])

        eyeGlyph.image = UIImage(systemName: "eye.fill")
        eyeGlyph.tintColor = .white
        eyeGlyph.contentMode = .scaleAspectFit
        eyeGlyph.translatesAutoresizingMaskIntoConstraints = false
        sensitiveLabel.text = "Sensitive content"
        sensitiveLabel.font = ShareCardFonts.sensitiveLabel
        sensitiveLabel.textColor = .white
        sensitiveLabel.translatesAutoresizingMaskIntoConstraints = false
        let spoilerStack = UIStackView(arrangedSubviews: [eyeGlyph, sensitiveLabel])
        spoilerStack.axis = .vertical
        spoilerStack.spacing = 8
        spoilerStack.alignment = .center
        spoilerStack.translatesAutoresizingMaskIntoConstraints = false
        spoilerOverlay.addSubview(spoilerStack)
        pinFilling(spoilerOverlay)
        NSLayoutConstraint.activate([
            eyeGlyph.widthAnchor.constraint(equalToConstant: 26),
            eyeGlyph.heightAnchor.constraint(equalToConstant: 22),
            spoilerStack.centerXAnchor.constraint(equalTo: spoilerOverlay.centerXAnchor),
            spoilerStack.centerYAnchor.constraint(equalTo: spoilerOverlay.centerYAnchor),
        ])
    }

    private func pinFilling(_ subview: UIView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subview)
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: trailingAnchor),
            subview.topAnchor.constraint(equalTo: topAnchor),
            subview.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Injects the loaded (or test) image. Task 5 wires this to
    /// `ImageServiceType.fetch`; snapshot tests inject a solid-color image so
    /// there is never a network dependency.
    func setMediaImage(_ image: UIImage?) {
        originalImage = image
        updatePresentation()
    }

    /// Applies media geometry (wide vs normal height), the NSFW spoiler state,
    /// and the palette.
    func configure(mediaAspectIsWide: Bool, isNsfw: Bool, nsfwRevealed: Bool, palette: ShareCardPalette) {
        heightConstraint.constant =
            (mediaAspectIsWide ? ShareCardMetrics.mediaWideHeightRatio : ShareCardMetrics.mediaHeightRatio)
                * ShareCardMetrics.contentWidth
        self.isNsfw = isNsfw
        self.nsfwRevealed = nsfwRevealed

        loadingContainer.backgroundColor = palette.chip
        loadingCaption.textColor = palette.faint
        shimmerHighlight.colors = [
            UIColor.white.withAlphaComponent(0).cgColor,
            UIColor.white.withAlphaComponent(0.14).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor,
        ]
        shimmerHighlight.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerHighlight.endPoint = CGPoint(x: 1, y: 0.5)
        // A 42%-black scrim, per the visual spec — a fixed literal, never a
        // dynamic system color, so it renders identically off-screen.
        spoilerOverlay.backgroundColor = UIColor(white: 0, alpha: 0.42)

        updatePresentation()
    }

    private func updatePresentation() {
        if let originalImage {
            loadingContainer.isHidden = true
            imageView.isHidden = false
            if isNsfw, !nsfwRevealed {
                imageView.image = Self.blurred(originalImage) ?? originalImage
                spoilerOverlay.isHidden = false
            } else {
                imageView.image = originalImage
                spoilerOverlay.isHidden = true
            }
        } else {
            imageView.isHidden = true
            imageView.image = nil
            loadingContainer.isHidden = false
            spoilerOverlay.isHidden = true
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The shimmer highlight is a vertical band parked off the left edge in
        // its model (static) state, so an off-screen render captures flat chip.
        let bandWidth = bounds.width * 0.5
        shimmerHighlight.frame = CGRect(x: -bandWidth, y: 0, width: bandWidth, height: bounds.height)
    }

    /// A `CIGaussianBlur` (radius 26) baked into a `UIImage`. Clamped to the
    /// input extent so the blur doesn't darken toward transparent edges, then
    /// cropped back to the original extent. Deterministic for a given input —
    /// a solid-color test image blurs to the same solid color.
    static func blurred(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input.clampedToExtent()
        filter.radius = 26
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
