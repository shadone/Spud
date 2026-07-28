//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// WCAG 2.x relative luminance and contrast-ratio arithmetic.
///
/// This is the measurement side of the "adequate contrast on every interactive
/// element" bar: it turns two colours — or two sampled pixels — into the single
/// number WCAG success criteria are written against, so a contrast claim can be
/// asserted instead of eyeballed. Accessibility audits on this codebase have
/// twice contradicted "looks fine", most recently the post-detail "Next new"
/// floating button, whose Liquid Glass conversion silently dropped it to
/// 1.55:1 on some accents.
///
/// Everything here is pure and deterministic; a dynamic `UIColor` is resolved
/// against an explicit trait collection so light and dark can each be measured.
///
/// Reference: WCAG 2.2, "relative luminance" and "contrast ratio" definitions.
public enum WCAGContrast {
    // MARK: - Thresholds

    /// WCAG AA for normal-size text (success criterion 1.4.3).
    ///
    /// "Normal" is anything below the large-text floor: under 18pt at a regular
    /// weight, or under 14pt bold.
    public static let aaNormalText: Double = 4.5

    /// WCAG AA for large text — 18pt regular or 14pt bold and above (1.4.3).
    public static let aaLargeText: Double = 3.0

    /// WCAG AA for user-interface components and graphical objects (1.4.11) —
    /// e.g. a control's fill against the backdrop it floats over.
    public static let aaNonText: Double = 3.0

    // MARK: - Relative luminance

    /// The WCAG relative luminance of an sRGB colour, in `0...1`.
    ///
    /// Components are expected in `0...1` and are linearised with the exact
    /// sRGB transfer function (the 0.04045 / 12.92 piecewise form), not with an
    /// approximate gamma — a 2.2 power approximation is off by enough near the
    /// dark end to move a borderline ratio across the AA line.
    ///
    /// Out-of-range components (which extended-range colour spaces such as
    /// Display P3 can produce when converted to sRGB) are clamped, so the
    /// result stays in `0...1`.
    public static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        0.2126 * linearized(red) + 0.7152 * linearized(green) + 0.0722 * linearized(blue)
    }

    /// The WCAG relative luminance of a colour, resolved for `traits`.
    ///
    /// Alpha is ignored: WCAG is defined over composited pixels, so a
    /// translucent colour must be flattened against its backdrop by the caller
    /// (or sampled from a rendered image) before it means anything.
    public static func relativeLuminance(of color: UIColor, in traits: UITraitCollection) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            // A pattern colour has no single RGB value; treat it as mid-grey so
            // callers get a finite (and unflattering) number rather than a trap.
            return relativeLuminance(red: 0.5, green: 0.5, blue: 0.5)
        }
        return relativeLuminance(red: Double(red), green: Double(green), blue: Double(blue))
    }

    // MARK: - Contrast ratio

    /// The WCAG contrast ratio between two relative luminances, in `1...21`.
    ///
    /// Symmetric — argument order does not matter.
    public static func ratio(betweenLuminance a: Double, and b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The WCAG contrast ratio between two colours resolved for `traits`, in
    /// `1...21`. Symmetric.
    public static func ratio(between a: UIColor, and b: UIColor, in traits: UITraitCollection) -> Double {
        ratio(
            betweenLuminance: relativeLuminance(of: a, in: traits),
            and: relativeLuminance(of: b, in: traits)
        )
    }

    // MARK: - Private

    /// The sRGB electro-optical transfer function: gamma-encoded channel to
    /// linear light.
    private static func linearized(_ component: Double) -> Double {
        let c = min(max(component, 0), 1)
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
}
