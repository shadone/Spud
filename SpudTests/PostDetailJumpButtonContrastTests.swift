//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUIKit
import Testing
import UIKit
@testable import Spud

/// Rendered-contrast coverage for the post-detail jump FAB
/// (``JumpButtonStyle``), the app's one floating action.
///
/// This exists because the control had **no** automated visual coverage, and
/// its Liquid Glass conversion silently took the "Next new" state from 3.62:1
/// down to as little as 1.55:1 — light-cyan text on a saturated accent capsule.
/// A snapshot reference would not have caught it: an illegible reference is
/// still a stable reference, and this initiative already shipped one as ground
/// truth. So the assertion here is on the number, not on the pixels matching a
/// stored image.
///
/// The accent is user-selectable across nine cases, and `UIGlassEffect` tints
/// from the inherited trait rather than the backdrop, so every accent is
/// measured in both light and dark. A fix tuned to one accent is not a fix.
///
/// Serialized: each test hosts a window on the shared foreground scene, and two
/// of them compositing at once would sample each other's pixels.
@MainActor
@Suite(.serialized)
struct PostDetailJumpButtonContrastTests {
    private static let styles: [UIUserInterfaceStyle] = [.light, .dark]

    private static func describe(_ accent: AccentColor, _ style: UIUserInterfaceStyle) -> Comment {
        "\(accent.rawValue) / \(style == .light ? "light" : "dark")"
    }

    /// The "Next new" capsule must clear WCAG AA for normal-size text (its
    /// title is 17pt regular — below the 18pt / 14pt-bold large-text floor, so
    /// 4.5:1 applies, not 3:1) for every accent in both appearances.
    @Test
    func nextNewCapsuleClearsAAForEveryAccent() throws {
        let probe = try RenderedContrastProbe()
        defer { probe.dismiss() }

        for accent in AccentColor.allCases {
            for style in Self.styles {
                let button = UIButton(configuration: JumpButtonStyle.configuration(isNew: true))
                let sample = try probe.measure(button: button, style: style, tint: accent.color)
                #expect(
                    sample.textRatio >= WCAGContrast.aaNormalText,
                    """
                    "Next new" title contrast \(sample.textRatio) is below AA \
                    (\(WCAGContrast.aaNormalText)) for \(Self.describe(accent, style)): \(sample.description)
                    """
                )
            }
        }
    }

    /// The capsule itself must be findable against the comment list it floats
    /// over — WCAG 1.4.11 for user-interface components.
    @Test
    func nextNewCapsuleIsDistinguishableFromTheContentBehindIt() throws {
        let probe = try RenderedContrastProbe()
        defer { probe.dismiss() }

        for accent in AccentColor.allCases {
            for style in Self.styles {
                let button = UIButton(configuration: JumpButtonStyle.configuration(isNew: true))
                let sample = try probe.measure(button: button, style: style, tint: accent.color)
                #expect(
                    sample.surfaceRatio >= WCAGContrast.aaNonText,
                    """
                    "Next new" capsule contrast against the backdrop is \(sample.surfaceRatio), \
                    below \(WCAGContrast.aaNonText) for \(Self.describe(accent, style))
                    """
                )
            }
        }
    }

    /// The default (no new comments) chevron is a glyph, not text, so the
    /// non-text bar applies to it. Measured separately because it uses the
    /// non-prominent `.glass()` material, which — unlike `prominentGlass()` —
    /// honours `baseForegroundColor` verbatim.
    @Test
    func defaultChevronClearsTheNonTextBarForEveryAccent() throws {
        let probe = try RenderedContrastProbe()
        defer { probe.dismiss() }

        for accent in AccentColor.allCases {
            for style in Self.styles {
                let button = UIButton(configuration: JumpButtonStyle.configuration(isNew: false))
                let sample = try probe.measure(button: button, style: style, tint: accent.color)
                #expect(
                    sample.textRatio >= WCAGContrast.aaNonText,
                    """
                    Default chevron contrast \(sample.textRatio) is below \(WCAGContrast.aaNonText) \
                    for \(Self.describe(accent, style)): \(sample.description)
                    """
                )
            }
        }
    }

    /// Proves the measurement above can actually fail.
    ///
    /// A contrast assertion is only worth having if it is sensitive to the
    /// defect it was written for, and a rendered-pixel probe has several ways to
    /// silently measure nothing (glass not compositing, an empty region, the
    /// wrong subview). So this reconstructs the exact configuration that
    /// shipped — `prominentGlass()` tinted with the accent, plus the
    /// `baseForegroundColor = .white` that turned out to be inert — and asserts
    /// that the probe reports it as *failing* AA on the default Lemmy accent.
    ///
    /// If this test ever passes AA, the probe has stopped measuring the real
    /// composited render; fix the probe before trusting the tests above.
    @Test
    func theShippedRegressionIsDetectedByTheProbe() throws {
        let probe = try RenderedContrastProbe()
        defer { probe.dismiss() }

        let accent = AccentColor.lemmy
        for style in Self.styles {
            var config = UIButton.Configuration.prominentGlass()
            config.title = "Next new"
            config.image = UIImage(systemName: "chevron.down")
            config.imagePlacement = .trailing
            config.imagePadding = 6
            config.cornerStyle = .capsule
            config.baseBackgroundColor = accent.color
            config.baseForegroundColor = .white
            let sample = try probe.measure(
                button: UIButton(configuration: config),
                style: style,
                tint: accent.color
            )
            #expect(
                sample.textRatio < WCAGContrast.aaNormalText,
                """
                The probe no longer detects the accent-tinted prominent-glass regression \
                (measured \(sample.textRatio) for \(Self.describe(accent, style))). The probe is \
                broken, not the app - the other tests in this suite cannot be trusted until it is fixed.
                """
            )
        }
    }

    /// `prominentGlass()` derives its label colour from its own background and
    /// ignores a light `baseForegroundColor` entirely. That is why the fix
    /// changes the *background* rather than the foreground, and why a future
    /// "just set the text to white" patch would be a no-op.
    ///
    /// Non-prominent `.glass()` behaves the opposite way, which is why
    /// `MediaViewerViewController` can (and does) rely on
    /// `baseForegroundColor = .white` there.
    @Test
    func prominentGlassIgnoresALightForegroundColor() throws {
        let probe = try RenderedContrastProbe()
        defer { probe.dismiss() }

        func capsule(foreground: UIColor?) -> UIButton {
            var config = UIButton.Configuration.prominentGlass()
            config.title = "Next new"
            config.cornerStyle = .capsule
            config.baseBackgroundColor = AccentColor.lemmy.color
            config.baseForegroundColor = foreground
            return UIButton(configuration: config)
        }

        let unset = try probe.measure(button: capsule(foreground: nil), style: .light, tint: AccentColor.lemmy.color)
        let white = try probe.measure(button: capsule(foreground: .white), style: .light, tint: AccentColor.lemmy.color)
        #expect(
            abs(unset.textRatio - white.textRatio) < 0.05,
            """
            prominentGlass() now honours a white foreground (unset \(unset.textRatio) vs \
            white \(white.textRatio)). Re-measure JumpButtonStyle - a foreground override may \
            have become a real lever.
            """
        )

        let black = try probe.measure(button: capsule(foreground: .black), style: .light, tint: AccentColor.lemmy.color)
        #expect(
            abs(black.textRatio - unset.textRatio) > 0.5,
            "prominentGlass() is expected to honour a dark foreground; measured \(black.textRatio) vs \(unset.textRatio)"
        )
    }
}
