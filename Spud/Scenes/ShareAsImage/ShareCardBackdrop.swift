//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreGraphics
import UIKit

/// Draws the decorative backdrop behind the card in the `.square` / `.story`
/// canvas modes: a soft `paper` radial gradient plus a fine dot grid. Kept in
/// its own file so ``ShareCardImageRenderer`` stays focused on composition and
/// export.
///
/// Everything is drawn with Core Graphics directly into the renderer's context
/// (no `UIVisualEffectView`, no `CAGradientLayer` to snapshot), so the output is
/// fully deterministic off-screen — the same requirement the card itself has.
/// The backdrop follows the CARD's chosen appearance (via the passed palette),
/// not the app theme.
enum ShareCardBackdrop {
    /// Grid spacing between dot centers, in points.
    static let dotSpacing: CGFloat = 22
    /// Radius of each grid dot, in points.
    static let dotRadius: CGFloat = 1
    /// The dots are drawn at 50% of the palette's `hair` opacity.
    static let dotHairFraction: CGFloat = 0.5

    /// Paints the radial gradient then the dot grid into `context`, filling
    /// `rect`. Call before drawing the card image on top.
    static func draw(in context: CGContext, rect: CGRect, palette: ShareCardPalette) {
        drawRadialBackground(in: context, rect: rect, palette: palette)
        drawDotGrid(in: context, rect: rect, palette: palette)
    }

    // MARK: - Radial background

    private static func drawRadialBackground(
        in context: CGContext,
        rect: CGRect,
        palette: ShareCardPalette
    ) {
        // A subtle central glow: slightly lifted at the center, settling to the
        // flat `paper` tone at the edges. Keeps the card feeling "placed" on a
        // surface rather than floating on a flat fill.
        let inner = blend(palette.paper, toward: .white, fraction: 0.06)
        let outer = palette.paper

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [inner.cgColor, outer.cgColor] as CFArray,
            locations: [0, 1]
        ) else {
            outer.setFill()
            context.fill(rect)
            return
        }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let endRadius = hypot(rect.width, rect.height) / 2
        context.saveGState()
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: endRadius,
            // Extend the end color to the corners the circle can't reach.
            options: [.drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    // MARK: - Dot grid

    private static func drawDotGrid(
        in context: CGContext,
        rect: CGRect,
        palette: ShareCardPalette
    ) {
        let baseAlpha = palette.hair.cgColor.alpha
        let dotColor = palette.hair.withAlphaComponent(baseAlpha * dotHairFraction)
        context.setFillColor(dotColor.cgColor)

        // Center the lattice so it reads as intentional rather than clipped at
        // the top-left; a half-spacing inset gives symmetric margins.
        var y = rect.minY + dotSpacing / 2
        while y <= rect.maxY {
            var x = rect.minX + dotSpacing / 2
            while x <= rect.maxX {
                let dot = CGRect(
                    x: x - dotRadius,
                    y: y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                context.fillEllipse(in: dot)
                x += dotSpacing
            }
            y += dotSpacing
        }
    }

    // MARK: - Color

    /// Linearly interpolates `color` toward `target` by `fraction` (0 = color,
    /// 1 = target) in RGB. Used to lift the gradient center off the flat paper
    /// tone.
    private static func blend(_ color: UIColor, toward target: UIColor, fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        target.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(max(fraction, 0), 1)
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }
}
