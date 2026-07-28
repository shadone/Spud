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

/// Rendered-contrast coverage for ``LowResPreviewPillView``, the small glass
/// pill shown over an image when only the cached thumbnail could be loaded.
///
/// The pill draws **fixed white** text and glyphs on `UIGlassEffect(.regular)`,
/// and that material takes its tint from the inherited trait rather than from
/// what is behind it. Under a light trait it therefore renders near-white — and
/// the white content on it disappears. The view pins
/// `overrideUserInterfaceStyle = .dark` to prevent exactly that; these tests
/// are the guard on the pin, plus ``pillWithoutItsDarkPinIsIllegible``, which
/// reconstructs the unpinned pill and proves the measurement can fail.
///
/// This matters more than usual here: the pill's snapshot reference was once
/// recorded *in* the illegible state and shipped as ground truth, because a
/// snapshot cannot tell "correct" from "stable". Pixels are covered separately
/// by `SpudSnapshotTests/LowResPreviewPillSnapshotTests`; legibility is
/// asserted here, as a number.
///
/// Backdrops are solid colours rather than photographs on purpose: the material
/// samples what is behind it, so a flat fill is both a faithful stand-in for a
/// uniform region of a photo and a reproducible one. `nearBlack` reproduces the
/// worst measured real case (a dark photo).
///
/// Serialized: each test hosts a window on the shared foreground scene, and two
/// of them compositing at once would sample each other's pixels.
@MainActor
@Suite(.serialized)
struct LowResPreviewPillContrastTests {
    private static let styles: [UIUserInterfaceStyle] = [.light, .dark]

    /// The three backdrop luminances the pill has to survive: a bright photo,
    /// a mid-tone one, and the near-black case the Increase Contrast audit
    /// measured as the worst.
    private static let backdrops: [(name: String, color: UIColor)] = [
        ("bright", UIColor(white: 0.95, alpha: 1)),
        ("mid", UIColor(white: 0.5, alpha: 1)),
        ("nearBlack", UIColor(white: 0.08, alpha: 1)),
    ]

    private static func describe(_ backdrop: String, _ style: UIUserInterfaceStyle) -> String {
        "\(backdrop) backdrop / \(style == .light ? "light" : "dark") trait"
    }

    /// Both shipped configurations: the post-detail header's interactive
    /// "tap to retry" pill and the media viewer's informational one.
    private static func pill(interactive: Bool) -> LowResPreviewPillView {
        LowResPreviewPillView(
            title: interactive ? "Low-res preview · tap to retry" : "Showing low-resolution preview",
            showsRetryHint: interactive
        )
    }

    /// The pill's label is 13pt medium — below the 18pt / 14pt-bold large-text
    /// floor — so WCAG AA for normal text applies, in every appearance and over
    /// every backdrop.
    @Test
    func pillTitleClearsAAOverEveryBackdrop() throws {
        let probe = try RenderedContrastProbe()
        defer { probe.dismiss() }

        for interactive in [true, false] {
            for (name, backdrop) in Self.backdrops {
                for style in Self.styles {
                    let sample = try probe.measure(
                        view: Self.pill(interactive: interactive),
                        style: style,
                        backdrop: backdrop
                    )
                    #expect(
                        sample.textRatio >= WCAGContrast.aaNormalText,
                        """
                        Low-res pill title contrast \(sample.textRatio) is below AA \
                        (\(WCAGContrast.aaNormalText)) for \(Self.describe(name, style)), \
                        interactive=\(interactive): \(sample.description)
                        """
                    )
                }
            }
        }
    }

    /// The retry chevron is the pill's affordance, and a glyph rather than
    /// text, so the non-text bar applies to it (WCAG 1.4.11).
    @Test
    func retryGlyphClearsTheNonTextBar() throws {
        let probe = try RenderedContrastProbe()
        defer { probe.dismiss() }

        for (name, backdrop) in Self.backdrops {
            for style in Self.styles {
                let sample = try probe.measure(
                    view: Self.pill(interactive: true),
                    style: style,
                    backdrop: backdrop,
                    content: { RenderedContrastProbe.firstSubview(of: $0, ofType: UIImageView.self) }
                )
                #expect(
                    sample.textRatio >= WCAGContrast.aaNonText,
                    """
                    Low-res pill glyph contrast \(sample.textRatio) is below \
                    \(WCAGContrast.aaNonText) for \(Self.describe(name, style)): \(sample.description)
                    """
                )
            }
        }
    }

    /// Proves the measurements above can actually fail.
    ///
    /// A contrast probe has several ways to silently measure nothing — glass
    /// not compositing, an empty region, the wrong subview — and a snapshot of
    /// a broken render is just as stable as a snapshot of a good one, which is
    /// how the illegible reference shipped. So this reconstructs the defect
    /// exactly: the shipping pill with its `overrideUserInterfaceStyle = .dark`
    /// pin removed, under a light trait, where the glass tints light and the
    /// fixed-white content vanishes into it.
    ///
    /// If this ever passes AA, the probe has stopped measuring the real
    /// composited render; fix the probe before trusting the tests above.
    @Test
    func pillWithoutItsDarkPinIsIllegible() throws {
        let probe = try RenderedContrastProbe()
        defer { probe.dismiss() }

        let unpinned = Self.pill(interactive: true)
        unpinned.overrideUserInterfaceStyle = .unspecified
        let sample = try probe.measure(
            view: unpinned,
            style: .light,
            backdrop: UIColor(white: 0.95, alpha: 1)
        )
        #expect(
            sample.textRatio < WCAGContrast.aaNormalText,
            """
            The probe no longer detects the unpinned-glass regression (measured \
            \(sample.textRatio)). The probe is broken, not the app - the other tests in \
            this suite cannot be trusted until it is fixed.
            """
        )
    }

    /// Over anything but a very dark backdrop the pill reads as a container in
    /// its own right — WCAG 1.4.11 for user-interface components.
    ///
    /// Measured on iPhone 17 Pro / iOS 26.3: 7.01:1 over a bright backdrop and
    /// 3.15:1 over a mid one, in both appearances. The near-black case is
    /// deliberately excluded and is covered by
    /// ``overANearBlackBackdropTheTextCarriesTheComponent`` — see that test for
    /// the reasoning.
    @Test
    func pillBoundaryIsFindableOverBrightAndMidBackdrops() throws {
        let probe = try RenderedContrastProbe()
        defer { probe.dismiss() }

        for (name, backdrop) in Self.backdrops where name != "nearBlack" {
            for style in Self.styles {
                let sample = try probe.measure(
                    view: Self.pill(interactive: true),
                    style: style,
                    backdrop: backdrop
                )
                #expect(
                    sample.edgeRatio >= WCAGContrast.aaNonText,
                    """
                    Low-res pill boundary contrast \(sample.edgeRatio) is below \
                    \(WCAGContrast.aaNonText) for \(Self.describe(name, style)) \
                    (edge \(sample.edge.rgbDescription), fill \(sample.fill.rgbDescription), \
                    backdrop \(sample.backdrop.rgbDescription), fill-only ratio \(sample.surfaceRatio))
                    """
                )
            }
        }
    }

    /// Over a near-black photo the pill's silhouette genuinely disappears —
    /// fill rgb(24) on backdrop rgb(20), 1.04:1, and even the material's
    /// brightest rim pixel only reaches 1.70:1. This is accepted rather than
    /// fixed, and this test is what keeps the acceptance honest.
    ///
    /// The reasoning: WCAG 1.4.11 asks for 3:1 on "visual information
    /// **required to identify**" a component. Here that information is the
    /// pill's own white text and glyph, not its fill — and those measure their
    /// *best* precisely where the silhouette measures its worst (14.5:1 over
    /// near-black, versus 6.9:1 over a bright backdrop). The two move in
    /// opposite directions because the material derives its fill from the
    /// backdrop, so there is no backdrop on which both are weak; a fill dark
    /// enough to vanish is a fill that makes white text maximally legible.
    /// Stroking a hairline visible against rgb(20) needs roughly 35% white,
    /// which is plainly visible over a bright photo too — it would trade a
    /// system material for a bespoke outlined box on every backdrop to fix one
    /// extreme where nothing is actually unreadable.
    ///
    /// So the invariant asserted here is the compensating one: over a
    /// near-black backdrop the text must be *exceptionally* legible (AAA, 7:1,
    /// well above the 4.5:1 the other tests require). A future change that
    /// weakens the text there — leaving neither a findable boundary nor
    /// legible content — fails.
    @Test
    func overANearBlackBackdropTheTextCarriesTheComponent() throws {
        let probe = try RenderedContrastProbe()
        defer { probe.dismiss() }

        let nearBlack = try #require(Self.backdrops.first { $0.name == "nearBlack" }).color
        for style in Self.styles {
            let sample = try probe.measure(
                view: Self.pill(interactive: true),
                style: style,
                backdrop: nearBlack
            )
            #expect(
                sample.textRatio >= 7,
                """
                Over a near-black backdrop the pill's boundary is invisible by design \
                (measured \(sample.edgeRatio)), so its text has to carry it - but the text \
                measures only \(sample.textRatio) for \(Self.describe("nearBlack", style)). \
                Neither the container nor its content is now findable; give the pill a \
                boundary or restore the text contrast.
                """
            )
        }
    }
}
