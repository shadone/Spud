//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUIKit
import SpudUtilKit
import Testing
import UIKit
@testable import Spud

/// Rendered-contrast coverage for the swipe-action tracks.
///
/// The upvote track's fill is the user's accent, and its glyph is a template SF
/// Symbol. `SwipeActionView` set no tint on the glyph, so it inherited the
/// window's — which this app sets to the accent as well. The arrow was drawn in
/// exactly its own background colour: 1.00:1, on all nine accents, in both
/// appearances. It was not faint; it was absent.
///
/// The tests here assert the two properties that were violated, rather than a
/// single ratio: the glyph must be **distinguishable** from the track, and its
/// colour must **not depend on the accent** — the latter being what makes an
/// accent-derived foreground impossible to reintroduce by accident.
///
/// Serialized: each test hosts a window on the shared foreground scene, and two
/// of them compositing at once would sample each other's pixels.
@MainActor
@Suite(.serialized)
struct SwipeActionGlyphContrastTests {
    private static let styles: [UIUserInterfaceStyle] = [.light, .dark]

    /// The bar this asserts is "visible", not WCAG 1.4.11's 3:1.
    ///
    /// Measured white-on-track: lemmy 3.68, blue 3.52/3.23, indigo 5.09/3.51,
    /// purple 4.17/3.63, pink 3.65/3.52, red 3.57/3.43 (light/dark) — six of
    /// nine accents clear 3:1 — against orange 2.31/2.23, green 2.22/2.02 and
    /// teal 2.16/1.86, which do not.
    ///
    /// No *accent-independent* glyph colour can clear 3:1 on all nine. The
    /// tracks span luminance 0.13 (indigo, Light) to 0.55 (teal, Dark); the
    /// darkest needs a foreground at or above 0.49 luminance, the brightest one
    /// at or below 0.15, and no colour is both. Clearing the bar everywhere
    /// therefore requires picking per track, which flips the arrow between
    /// black and white as the user changes accent — rendered, looked at, and
    /// rejected as reading like a bug rather than a swipe action.
    ///
    /// So this floor guards what actually regressed: a glyph drawn in its own
    /// background colour, which measured 1.00:1 and was not rendered at all.
    private static let visibleFloor: Double = 1.8

    /// Reproduces the composition `SwipeActionView` builds: the action's own
    /// track fill, with the action's own template glyph on it.
    ///
    /// Built from the shipping presentation (`SwipeAction.image` /
    /// `.backgroundColor`) and the shipping view's glyph tint, rather than from
    /// literals, so the test measures what the app draws. The real
    /// `SwipeActionView` cannot be measured directly: its track has zero width
    /// until a pan gesture opens it.
    private static func track(for action: SwipeAction, tinted: Bool) -> UIView {
        let appearance = GeneralAppearance()
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 72, height: 56))
        container.backgroundColor = action.backgroundColor(appearance: appearance)
        // The probe places its subject with centring constraints, so the track
        // has to state its own size or it collapses to nothing and the glyph
        // ends up sampled against the probe's backdrop instead of the fill.
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 72),
            container.heightAnchor.constraint(equalToConstant: 56),
        ])

        let glyph = UIImageView(image: action.image(state: SwipeActionState(), appearance: appearance))
        glyph.contentMode = .scaleAspectFit
        glyph.frame = CGRect(x: 16, y: 8, width: 40, height: 40)
        // `tinted: false` is the shipped defect - no tint of its own, so the
        // glyph inherits the accent from the container below.
        if tinted {
            glyph.tintColor = SwipeActionViewGlyphColorProbe.glyphColor
        }
        container.addSubview(glyph)
        return container
    }

    /// The accent-filled upvote track is the accent-on-accent case. Its glyph
    /// must be visible on every accent, in both appearances.
    @Test
    func upvoteGlyphIsVisibleOnEveryAccent() throws {
        let probe = try RenderedContrastProbe()
        defer { probe.dismiss() }

        for accent in AccentColor.allCases {
            ThemeManager.shared.setAccent(accent)
            for style in Self.styles {
                let sample = try probe.measure(
                    view: Self.track(for: .upvote, tinted: true),
                    style: style,
                    tint: accent.color,
                    backdrop: .systemBackground
                )
                #expect(
                    sample.textRatio >= Self.visibleFloor,
                    """
                    Upvote swipe glyph contrast \(sample.textRatio) is below \(Self.visibleFloor) \
                    for \(accent.rawValue) / \(style == .light ? "light" : "dark"): \(sample.description)
                    """
                )
            }
        }
        ThemeManager.shared.setAccent(.lemmy)
    }

    /// The glyph's rendered colour must be the same whatever the accent.
    ///
    /// This is the assertion that actually pins the defect shut. A ratio floor
    /// alone would still pass a future foreground that merely *tints toward*
    /// the accent; requiring the sampled glyph to be accent-independent makes
    /// "derive the glyph from the fill" impossible to reintroduce quietly.
    @Test
    func upvoteGlyphColourDoesNotFollowTheAccent() throws {
        let probe = try RenderedContrastProbe()
        defer { probe.dismiss() }

        var sampled: [AccentColor: UIColor] = [:]
        for accent in AccentColor.allCases {
            ThemeManager.shared.setAccent(accent)
            sampled[accent] = try probe.measure(
                view: Self.track(for: .upvote, tinted: true),
                style: .light,
                tint: accent.color,
                backdrop: .systemBackground
            ).text
        }
        ThemeManager.shared.setAccent(.lemmy)

        let reference = try #require(sampled[.lemmy])
        for (accent, color) in sampled {
            #expect(
                color.isVisuallyEqual(to: reference),
                """
                The swipe glyph renders \(color.rgbDescription) on the \(accent.rawValue) accent but \
                \(reference.rgbDescription) on lemmy - its colour is following the accent again, which \
                is what made the arrow invisible on the accent-filled upvote track.
                """
            )
        }
    }

    /// Proves the measurement can fail: the untinted glyph — exactly what
    /// shipped — must come out indistinguishable from its track.
    ///
    /// If this ever reports contrast, either the window tint no longer cascades
    /// into the swipe glyph or the probe has stopped measuring the real render;
    /// either way the test above is no longer evidence of anything.
    @Test
    func theUntintedGlyphIsDetectedAsInvisible() throws {
        let probe = try RenderedContrastProbe()
        defer { probe.dismiss() }

        for accent in AccentColor.allCases {
            ThemeManager.shared.setAccent(accent)
            let sample = try probe.measure(
                view: Self.track(for: .upvote, tinted: false),
                style: .light,
                tint: accent.color,
                backdrop: .systemBackground
            )
            #expect(
                sample.textRatio < 1.1,
                """
                The probe no longer detects an accent glyph on the accent-filled upvote track \
                (measured \(sample.textRatio) for \(accent.rawValue)). The probe is broken, not the \
                app - the tests above cannot be trusted until it is fixed.
                """
            )
        }
        ThemeManager.shared.setAccent(.lemmy)
    }
}

/// Reaches the private glyph colour `SwipeActionView` applies, so the tests
/// measure the shipping value rather than a copy of it that could drift.
private enum SwipeActionViewGlyphColorProbe {
    static var glyphColor: UIColor {
        let view = SwipeActionView(contentView: UIView(), margin: .zero, configuration: nil)
        return view.leadingSwipeActionImageView.tintColor
    }
}

private extension UIColor {
    /// Equal to within one 8-bit step per channel — enough to absorb render
    /// rounding without absorbing a real colour change.
    func isVisuallyEqual(to other: UIColor) -> Bool {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let tolerance: CGFloat = 2 / 255
        return abs(r1 - r2) <= tolerance && abs(g1 - g2) <= tolerance && abs(b1 - b2) <= tolerance
    }
}
