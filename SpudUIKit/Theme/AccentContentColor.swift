//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Derives the **content** variant of an accent colour: the luminance-corrected
/// value to use when the accent is drawn *as text* or *as a meaningful glyph*,
/// rather than as a fill.
///
/// ## Why a second value exists
///
/// The nine ``AccentColor`` cases are tuned to look right as a **surface** — a
/// vote capsule, a swipe track, a filled button. Used as a foreground on the
/// app's ordinary light backgrounds several of them are illegible: measured
/// across the palette, Orange, Green and Teal land near 2.2:1 and even the
/// default Lemmy teal only reaches 3.7:1, against the 4.5:1 WCAG AA asks for
/// normal-size text (and the 3:1 it asks for meaningful glyphs). That is a
/// property of the palette, not of any one screen, so it is fixed once here
/// instead of twenty times at the call sites.
///
/// Darkening the *fill* was tried on this codebase and rejected — it turns
/// Orange to brown and Green to olive on a surface the eye reads as a swatch.
/// Splitting the two jobs keeps the vivid fill exactly as it is and pays the
/// darkening only where legibility is the point.
///
/// ## How the value is derived
///
/// The variant is **computed**, never hand-picked, so it cannot drift out of
/// step with a palette edit: the accent is moved along a single axis — towards
/// black in Light, towards white in Dark — by the smallest amount that clears
/// ``minimumRatio`` against ``referenceBackground(behind:style:)``.
///
/// Both moves are affine in gamma-encoded sRGB (`c -> c * (1 - t)` and
/// `c -> c + (1 - c) * t`), which **preserves hue exactly**: they scale the
/// max-minus-min channel spread without reordering channels, so the HSB hue
/// angle is unchanged and Orange can never quietly become Brown-the-hue. Only
/// brightness (and, in the rare second phase of a lighten, saturation) moves.
///
/// ## What the reference background is, and why it is not just white
///
/// Accent text in this app very often sits on the accent's own low-alpha wash —
/// the "N new" banner, the OP badge, the momentum and filter chips, the
/// subscribe pill. That wash is the realistic worst case, and it is
/// meaningfully darker than plain white, so deriving against white would leave
/// exactly those surfaces short. The reference is therefore the vivid accent at
/// ``maximumWashAlpha`` composited over the least-forgiving ordinary system
/// surface for the appearance: the *darkest* light one and the *lightest* dark
/// one. Any plain-background site then clears the bar with room to spare.
public enum AccentContentColor {
    /// The largest alpha any accent wash in the app is drawn at.
    ///
    /// Washes range from 0.08 (the register application note) to 0.16 (the
    /// new-comments banner and the OP badge). A site that wants a *heavier*
    /// wash than this behind accent text must raise this constant — and re-run
    /// `AccentContentColorTests`, which will fail until the derivation is
    /// re-tightened.
    public static let maximumWashAlpha: CGFloat = 0.16

    /// The worst-case surface accent content is expected to be drawn on.
    ///
    /// - In Light this is `systemGroupedBackground` (the darkest ordinary light
    ///   surface) under a full-strength accent wash.
    /// - In Dark it is `tertiarySystemBackground` (the lightest ordinary dark
    ///   surface) under the same wash, because in Dark a wash makes the
    ///   backdrop *lighter*, which is what hurts light-on-dark text.
    public static func referenceBackground(behind accent: UIColor, style: UIUserInterfaceStyle) -> UIColor {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let base: UIColor = style == .dark ? .tertiarySystemBackground : .systemGroupedBackground
        let surface = components(of: base, in: traits)
        let wash = components(of: accent, in: traits)
        let alpha = Double(maximumWashAlpha)
        return UIColor(
            red: wash.red * alpha + surface.red * (1 - alpha),
            green: wash.green * alpha + surface.green * (1 - alpha),
            blue: wash.blue * alpha + surface.blue * (1 - alpha),
            alpha: 1
        )
    }

    /// The content variant of `accent` for one appearance.
    ///
    /// Returns `accent` resolved for `style` unchanged when it already clears
    /// `minimumRatio` — several accents (Blue, Indigo, Purple, Red) need no
    /// correction at all in Light, and most of the palette needs none in Dark.
    ///
    /// - Parameter minimumRatio: the WCAG ratio to clear. Defaults to AA for
    ///   normal-size text, which is the strongest bar any accent-as-content
    ///   site in the app is held to, so glyph sites (3:1) get it for free.
    public static func derived(
        from accent: UIColor,
        style: UIUserInterfaceStyle,
        minimumRatio: Double = WCAGContrast.aaNormalText
    ) -> UIColor {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let base = components(of: accent, in: traits)
        let backgroundLuminance = WCAGContrast.relativeLuminance(
            of: referenceBackground(behind: accent, style: style),
            in: traits
        )

        func ratio(_ rgb: RGB) -> Double {
            WCAGContrast.ratio(
                betweenLuminance: WCAGContrast.relativeLuminance(red: rgb.red, green: rgb.green, blue: rgb.blue),
                and: backgroundLuminance
            )
        }

        guard ratio(base) < minimumRatio else { return base.uiColor }

        // Pick the direction that can actually reach the bar. On a light
        // backdrop only darkening can (white against a light surface is
        // hopeless), and vice versa; when both work — a mid-luminance
        // backdrop — take the one that reaches the bar with the smaller move.
        let darkenReach = ratio(darkened(base, by: 1))
        let lightenReach = ratio(lightened(base, by: 1))
        let shouldDarken: Bool
        if darkenReach >= minimumRatio, lightenReach >= minimumRatio {
            shouldDarken = backgroundLuminance > WCAGContrast.relativeLuminance(
                red: base.red, green: base.green, blue: base.blue
            )
        } else {
            shouldDarken = darkenReach >= lightenReach
        }

        func move(_ rgb: RGB, _ t: Double) -> RGB {
            shouldDarken ? darkened(rgb, by: t) : lightened(rgb, by: t)
        }

        // Both moves are monotonic in contrast against the backdrop, so a
        // bisection on `t` converges on the least-changed value that clears the
        // bar. 24 steps resolves `t` far finer than an 8-bit channel can hold.
        var low = 0.0
        var high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if ratio(move(base, mid)) >= minimumRatio {
                high = mid
            } else {
                low = mid
            }
        }
        return move(base, high).uiColor
    }

    /// The content variant of `accent` as a **dynamic** colour that resolves
    /// per trait collection.
    ///
    /// Both appearances are derived up front and the provider only selects
    /// between them, so a trait change (or a `resolvedColor(with:)` in a test)
    /// always gets the right one — a value flattened once at read time would be
    /// stale the moment the user switched appearance.
    public static func dynamic(
        from accent: UIColor,
        minimumRatio: Double = WCAGContrast.aaNormalText
    ) -> UIColor {
        let light = derived(from: accent, style: .light, minimumRatio: minimumRatio)
        let dark = derived(from: accent, style: .dark, minimumRatio: minimumRatio)
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }

    // MARK: - Private

    /// A resolved, opaque sRGB triple in `0...1`.
    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        var uiColor: UIColor {
            UIColor(red: red, green: green, blue: blue, alpha: 1)
        }
    }

    /// Towards black. `c * (1 - t)` — hue and saturation are untouched.
    private static func darkened(_ rgb: RGB, by t: Double) -> RGB {
        RGB(red: rgb.red * (1 - t), green: rgb.green * (1 - t), blue: rgb.blue * (1 - t))
    }

    /// Towards white, in two phases.
    ///
    /// The first phase scales every channel up until the brightest one
    /// saturates — that is a pure HSB brightness increase, so hue *and*
    /// saturation survive; the Lemmy accent needs nothing more than this. Only
    /// once the colour is out of brightness headroom does the second phase
    /// blend towards white, which keeps the hue angle but does wash the colour
    /// out. Most of the palette's Dark values already peg a channel at 1.0, so
    /// for them the whole move is the second phase.
    private static func lightened(_ rgb: RGB, by t: Double) -> RGB {
        let peak = max(rgb.red, rgb.green, rgb.blue)
        let headroom = peak > 0 ? 1 / peak : 1
        // How much of `t` the brightness phase gets. Zero when the colour is
        // already at full brightness - otherwise the whole move would collapse
        // into a scale by 1.0, i.e. no move at all.
        let brightnessPhase = headroom > 1 ? 0.5 : 0.0

        if t <= brightnessPhase, brightnessPhase > 0 {
            let scale = 1 + (headroom - 1) * (t / brightnessPhase)
            return RGB(red: rgb.red * scale, green: rgb.green * scale, blue: rgb.blue * scale)
        }

        let peaked = RGB(red: rgb.red * headroom, green: rgb.green * headroom, blue: rgb.blue * headroom)
        let blend = (t - brightnessPhase) / (1 - brightnessPhase)
        return RGB(
            red: peaked.red + (1 - peaked.red) * blend,
            green: peaked.green + (1 - peaked.green) * blend,
            blue: peaked.blue + (1 - peaked.blue) * blend
        )
    }

    private static func components(of color: UIColor, in traits: UITraitCollection) -> RGB {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return RGB(red: 0.5, green: 0.5, blue: 0.5)
        }
        return RGB(
            red: Double(min(max(red, 0), 1)),
            green: Double(min(max(green, 0), 1)),
            blue: Double(min(max(blue, 0), 1))
        )
    }
}
