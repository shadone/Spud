//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// Measures the **rendered** WCAG contrast of a control, by compositing it for
/// real and sampling the resulting pixels.
///
/// Reading `baseForegroundColor` back off a `UIButton.Configuration` is not a
/// contrast measurement and can be actively misleading: `prominentGlass()`
/// blends the foreground into its own background tint, so a configuration that
/// says `.white` renders as a light tint of the background instead. Only a
/// composited render tells the truth, which is why this goes through the
/// window server rather than `layer.render(in:)` — the latter does not
/// composite glass at all.
///
/// ## Why this does not poison snapshot captures
///
/// The host window is attached to the test host's foreground scene and made
/// **visible but never key**. swift-snapshot-testing's on-screen strategies
/// resolve their host through `getKeyWindow()`, so a window that never becomes
/// key cannot be picked up by a later capture. An ad hoc `makeKeyAndVisible()`
/// here would corrupt every subsequent on-screen snapshot for the rest of the
/// simulator boot — see `SpudSnapshotTests/CLAUDE.md`. A non-visible window is
/// not an option either: it never lays out, so there would be nothing to
/// measure.
@MainActor
final class RenderedContrastProbe {
    /// One measured control.
    struct Sample {
        /// The surface immediately behind the glyphs (the control's own fill).
        let fill: UIColor
        /// The rendered glyph colour — the pixel furthest in luminance from
        /// `fill`, i.e. the core of an antialiased glyph.
        let text: UIColor
        /// The backdrop just outside the control.
        let backdrop: UIColor

        /// Text against the control's fill — WCAG 1.4.3.
        let textRatio: Double
        /// The control's fill against the backdrop it floats over — WCAG 1.4.11.
        let surfaceRatio: Double

        var description: String {
            "text \(text.rgbDescription) on \(fill.rgbDescription)"
        }
    }

    private let window: UIWindow
    private let container: UIView
    private let scale: CGFloat

    /// - Throws: if the test host has no foreground scene, which a real safe
    ///   area and on-screen compositing both depend on.
    init() throws {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            throw ProbeError.noForegroundScene
        }
        window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = UIViewController()
        // Visible, never key - see the type's doc comment.
        window.isHidden = false
        scale = scene.screen.scale
        container = UIView(frame: CGRect(x: 0, y: 120, width: 360, height: 120))
        window.rootViewController?.view.addSubview(container)
    }

    enum ProbeError: Error {
        case noForegroundScene
        case renderFailed
        case noMeasurableContent
    }

    /// Tears the host window down. Call from a `defer` in the test.
    func dismiss() {
        container.removeFromSuperview()
        window.isHidden = true
        window.rootViewController = nil
    }

    /// Composites `button` over `backdrop` in `style` with `tint` inherited,
    /// and measures its rendered contrast.
    func measure(
        button: UIButton,
        style: UIUserInterfaceStyle,
        tint: UIColor,
        backdrop: UIColor = .systemBackground
    ) throws -> Sample {
        window.overrideUserInterfaceStyle = style
        container.tintColor = tint
        container.backgroundColor = backdrop
        container.subviews.forEach { $0.removeFromSuperview() }

        button.sizeToFit()
        button.frame = CGRect(
            x: 24,
            y: (container.bounds.height - button.bounds.height) / 2,
            width: button.bounds.width,
            height: button.bounds.height
        )
        container.addSubview(button)
        settle()

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(bounds: container.bounds, format: format).image { _ in
            _ = container.drawHierarchy(in: container.bounds, afterScreenUpdates: true)
        }
        guard let pixels = Pixels(image) else { throw ProbeError.renderFailed }

        // Prefer the title; an image-only control is measured on its glyph.
        // A configuration-based button builds its own private label / image
        // view, so find them by walking the hierarchy rather than through the
        // legacy `titleLabel` / `imageView` accessors.
        let contentView: UIView? = Self.firstSubview(of: button, ofType: UILabel.self)
            ?? Self.firstSubview(of: button, ofType: UIImageView.self)
        guard let contentView, case let contentRect = contentView.convert(contentView.bounds, to: container),
              !contentRect.isEmpty
        else {
            throw ProbeError.noMeasurableContent
        }
        guard let region = pixels.region(of: contentRect, scale: scale) else {
            throw ProbeError.noMeasurableContent
        }

        let fill = region.modalColor
        let text = region.colorFurthestInLuminance(from: fill)
        let buttonRect = button.convert(button.bounds, to: container)
        let backdropSample = pixels.color(
            atX: Int((buttonRect.minX - 6) * scale),
            y: Int(buttonRect.midY * scale)
        )

        return Sample(
            fill: fill.uiColor,
            text: text.uiColor,
            backdrop: backdropSample.uiColor,
            textRatio: WCAGContrast.ratio(betweenLuminance: fill.luminance, and: text.luminance),
            surfaceRatio: WCAGContrast.ratio(betweenLuminance: fill.luminance, and: backdropSample.luminance)
        )
    }

    private static func firstSubview<T: UIView>(of view: UIView, ofType type: T.Type) -> T? {
        for subview in view.subviews {
            if let match = subview as? T { return match }
            if let match = firstSubview(of: subview, ofType: type) { return match }
        }
        return nil
    }

    private func settle() {
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date())
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
}

// MARK: - Pixel sampling

/// A sampled sRGB pixel.
struct SampledColor {
    let red: Double
    let green: Double
    let blue: Double

    var luminance: Double {
        WCAGContrast.relativeLuminance(red: red, green: green, blue: blue)
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

/// A rectangular block of sampled pixels.
struct PixelRegion {
    let colors: [SampledColor]

    /// The most common colour, quantised to 5 bits per channel and then
    /// averaged over the exact pixels in that bucket.
    ///
    /// For a text region this is the surface *behind* the glyphs: glyph
    /// coverage inside a label's bounds is well under half, so the background
    /// always wins the vote. Sampling a fixed corner instead would pick up the
    /// capsule's specular rim.
    var modalColor: SampledColor {
        var histogram: [Int: [SampledColor]] = [:]
        for color in colors {
            let key = quantize(color)
            histogram[key, default: []].append(color)
        }
        let bucket = histogram.max { $0.value.count < $1.value.count }?.value ?? colors
        let count = Double(bucket.count)
        return SampledColor(
            red: bucket.reduce(0) { $0 + $1.red } / count,
            green: bucket.reduce(0) { $0 + $1.green } / count,
            blue: bucket.reduce(0) { $0 + $1.blue } / count
        )
    }

    /// The pixel whose luminance is furthest from `reference` — the core of an
    /// antialiased glyph, i.e. the colour the text actually renders as.
    func colorFurthestInLuminance(from reference: SampledColor) -> SampledColor {
        let target = reference.luminance
        return colors.max { abs($0.luminance - target) < abs($1.luminance - target) } ?? reference
    }

    private func quantize(_ color: SampledColor) -> Int {
        let r = Int(color.red * 255) >> 3
        let g = Int(color.green * 255) >> 3
        let b = Int(color.blue * 255) >> 3
        return r << 10 | g << 5 | b
    }
}

/// An RGBA byte buffer decoded from a rendered image, in sRGB.
struct Pixels {
    private let bytes: [UInt8]
    private let width: Int
    private let height: Int

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        width = cgImage.width
        height = cgImage.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = data
    }

    func color(atX x: Int, y: Int) -> SampledColor {
        let cx = min(max(x, 0), width - 1)
        let cy = min(max(y, 0), height - 1)
        let i = (cy * width + cx) * 4
        return SampledColor(
            red: Double(bytes[i]) / 255,
            green: Double(bytes[i + 1]) / 255,
            blue: Double(bytes[i + 2]) / 255
        )
    }

    func region(of rect: CGRect, scale: CGFloat) -> PixelRegion? {
        let x0 = max(0, Int(rect.minX * scale))
        let x1 = min(width - 1, Int(rect.maxX * scale))
        let y0 = max(0, Int(rect.minY * scale))
        let y1 = min(height - 1, Int(rect.maxY * scale))
        guard x1 > x0, y1 > y0 else { return nil }
        var colors: [SampledColor] = []
        colors.reserveCapacity((x1 - x0 + 1) * (y1 - y0 + 1))
        for y in y0...y1 {
            for x in x0...x1 {
                colors.append(color(atX: x, y: y))
            }
        }
        return PixelRegion(colors: colors)
    }
}

extension UIColor {
    /// `rgb(r,g,b)` at 8 bits per channel, for failure messages.
    var rgbDescription: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgb(\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255)))"
    }
}
