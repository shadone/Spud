//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
import UIKit
@testable import SpudUIKit

/// The palette-level contrast guarantee: every accent, used as **content**,
/// clears WCAG AA for normal-size text in both appearances.
///
/// This is the assertion the accent palette previously had no answer to.
/// Orange, Green and Teal measured around 2.2:1 as foreground text on the
/// app's light backgrounds, and even the default Lemmy teal only reached
/// 3.7:1 — below the 4.5:1 bar and, for the glyph sites, sometimes below 3:1
/// too. A table in a document would rot; these assertions cannot.
///
/// ``regressionIsDetectedByTheseAssertions`` is the canary: it pins the fact
/// that the *fill* accents genuinely fail, so a future change that silently
/// makes the measurement inert (a background resolved wrong, a ratio computed
/// against itself) fails loudly instead of certifying everything green.
struct AccentContentColorTests {
    private static let styles: [UIUserInterfaceStyle] = [.light, .dark]

    private static func describe(_ accent: AccentColor, _ style: UIUserInterfaceStyle) -> Comment {
        "\(accent.rawValue) / \(style == .light ? "light" : "dark")"
    }

    private static func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(userInterfaceStyle: style)
    }

    // MARK: - The contrast guarantee

    /// Every accent's content variant clears AA for normal text against the
    /// worst case it is derived for: its own full-strength wash over the
    /// least-forgiving ordinary system surface.
    @Test
    func everyAccentClearsAAOnItsWorstCaseBackground() {
        for accent in AccentColor.allCases {
            for style in Self.styles {
                let background = AccentContentColor.referenceBackground(behind: accent.color, style: style)
                let ratio = WCAGContrast.ratio(
                    between: accent.contentColor,
                    and: background,
                    in: Self.traits(style)
                )
                #expect(
                    ratio >= WCAGContrast.aaNormalText,
                    """
                    Content accent contrast \(ratio) is below AA (\(WCAGContrast.aaNormalText)) \
                    for \(Self.describe(accent, style)) on its own wash
                    """
                )
            }
        }
    }

    /// The same guarantee on the plain surfaces accent text lands on when there
    /// is no wash behind it. These are strictly easier than the wash case, so
    /// they are a cross-check that the reference background really is the worst
    /// case rather than an accidentally lenient one.
    @Test
    func everyAccentClearsAAOnThePlainSystemSurfaces() {
        let surfaces: [(String, UIColor)] = [
            ("systemBackground", .systemBackground),
            ("secondarySystemBackground", .secondarySystemBackground),
            ("tertiarySystemBackground", .tertiarySystemBackground),
            ("systemGroupedBackground", .systemGroupedBackground),
            ("secondarySystemGroupedBackground", .secondarySystemGroupedBackground),
        ]
        for accent in AccentColor.allCases {
            for style in Self.styles {
                for (name, surface) in surfaces {
                    let ratio = WCAGContrast.ratio(
                        between: accent.contentColor,
                        and: surface,
                        in: Self.traits(style)
                    )
                    #expect(
                        ratio >= WCAGContrast.aaNormalText,
                        """
                        Content accent contrast \(ratio) is below AA (\(WCAGContrast.aaNormalText)) \
                        for \(Self.describe(accent, style)) on \(name)
                        """
                    )
                }
            }
        }
    }

    /// Proves the assertions above can fail.
    ///
    /// The four accents named here are the ones the audit measured as
    /// illegible-as-text in Light. If any of them ever *passes* the bar as a
    /// raw fill, either the palette changed (update this list) or the
    /// measurement stopped measuring, and the guarantees above are worthless
    /// until that is understood.
    @Test
    func regressionIsDetectedByTheseAssertions() {
        for accent in [AccentColor.lemmy, .orange, .green, .teal] {
            let background = AccentContentColor.referenceBackground(behind: accent.color, style: .light)
            let ratio = WCAGContrast.ratio(between: accent.color, and: background, in: Self.traits(.light))
            #expect(
                ratio < WCAGContrast.aaNormalText,
                """
                The raw fill accent \(accent.rawValue) now measures \(ratio) in light, at or above AA. \
                Either the palette changed or the measurement is inert - the contrast guarantees in \
                this suite cannot be trusted until this is explained.
                """
            )
        }
    }

    // MARK: - Staying recognisably the same colour

    /// The content variant must stay the same hue as the fill it stands in for.
    ///
    /// The derivation moves along an axis that preserves the HSB hue angle
    /// exactly, so the tolerance here is a guard against a future *hand-picked*
    /// pair sneaking in, not slack the current implementation needs: an Orange
    /// that quietly became Brown-the-hue, or a Teal that drifted to Blue, would
    /// break the promise that the picker's swatch predicts what the app looks
    /// like.
    @Test
    func contentVariantKeepsTheAccentHue() {
        for accent in AccentColor.allCases {
            for style in Self.styles {
                let traits = Self.traits(style)
                let fill = accent.color.resolvedColor(with: traits)
                let content = accent.contentColor.resolvedColor(with: traits)

                var fillHue: CGFloat = 0, fillSaturation: CGFloat = 0, fillBrightness: CGFloat = 0, alpha: CGFloat = 0
                var contentHue: CGFloat = 0, contentSaturation: CGFloat = 0, contentBrightness: CGFloat = 0
                #expect(fill.getHue(&fillHue, saturation: &fillSaturation, brightness: &fillBrightness, alpha: &alpha))
                #expect(content.getHue(
                    &contentHue,
                    saturation: &contentSaturation,
                    brightness: &contentBrightness,
                    alpha: &alpha
                ))

                let rawDelta = abs(fillHue - contentHue)
                let hueDelta = min(rawDelta, 1 - rawDelta)
                #expect(
                    hueDelta <= 0.02,
                    """
                    Content accent hue drifted by \(hueDelta * 360) degrees for \(Self.describe(accent, style)) \
                    (fill \(fillHue * 360), content \(contentHue * 360))
                    """
                )
            }
        }
    }

    /// The content variant must still read as a colour, not as a near-grey.
    ///
    /// Darkening far enough would eventually reach black, and lightening far
    /// enough would reach white; both clear every contrast bar and communicate
    /// nothing. Darkening never costs saturation at all here. Lightening does
    /// once a channel is already pegged at 1.0 — six of the Dark values are —
    /// so the bar is "keeps two thirds of the fill's saturation, and never
    /// falls to a near-grey". The palest correction in the palette today is
    /// Indigo in Dark, which keeps 76% of its saturation and lands at 0.44.
    @Test
    func contentVariantStaysSaturated() {
        for accent in AccentColor.allCases {
            for style in Self.styles {
                let traits = Self.traits(style)
                var fillSaturation: CGFloat = 0, contentSaturation: CGFloat = 0
                var hue: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
                _ = accent.color.resolvedColor(with: traits)
                    .getHue(&hue, saturation: &fillSaturation, brightness: &brightness, alpha: &alpha)
                _ = accent.contentColor.resolvedColor(with: traits)
                    .getHue(&hue, saturation: &contentSaturation, brightness: &brightness, alpha: &alpha)
                #expect(
                    contentSaturation >= fillSaturation * 0.66,
                    """
                    Content accent lost too much saturation for \(Self.describe(accent, style)): \
                    \(fillSaturation) -> \(contentSaturation)
                    """
                )
                #expect(
                    contentSaturation >= min(fillSaturation, 0.3),
                    """
                    Content accent is washed out to a near-grey for \(Self.describe(accent, style)): \
                    saturation \(contentSaturation)
                    """
                )
            }
        }
    }

    // MARK: - The fill accent is untouched

    /// The vivid fill palette must not move. Vote capsules, swipe tracks and
    /// the prominent buttons were tuned against these exact values, and
    /// darkening them was tried and rejected.
    @Test
    func fillAccentsAreUnchanged() {
        #expect(AccentColor.blue.color == .systemBlue)
        #expect(AccentColor.indigo.color == .systemIndigo)
        #expect(AccentColor.purple.color == .systemPurple)
        #expect(AccentColor.pink.color == .systemPink)
        #expect(AccentColor.red.color == .systemRed)
        #expect(AccentColor.orange.color == .systemOrange)
        #expect(AccentColor.green.color == .systemGreen)
        #expect(AccentColor.teal.color == .systemTeal)

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        _ = AccentColor.lemmy.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(abs(red - 0.0) < 0.001)
        #expect(abs(green - 0.59) < 0.001)
        #expect(abs(blue - 0.53) < 0.001)
    }

    /// A colour that is already legible as content is returned untouched — the
    /// correction is applied only where it is needed, and never "just a bit
    /// more for safety".
    ///
    /// Every one of the nine shipped accents needs *some* correction in Light,
    /// so this uses a colour outside the palette (a deep navy) that comfortably
    /// clears the bar on its own.
    @Test
    func anAlreadyLegibleColourIsReturnedUnchanged() {
        let navy = UIColor(red: 0.04, green: 0.12, blue: 0.42, alpha: 1)
        let traits = Self.traits(.light)
        let background = AccentContentColor.referenceBackground(behind: navy, style: .light)
        let fillRatio = WCAGContrast.ratio(between: navy, and: background, in: traits)
        #expect(fillRatio >= WCAGContrast.aaNormalText, "fixture no longer clears AA (\(fillRatio))")

        let derived = AccentContentColor.derived(from: navy, style: .light)
        #expect(
            derived.resolvedColor(with: traits) == navy.resolvedColor(with: traits),
            "an already-legible colour was altered: \(navy) -> \(derived)"
        )
    }

    // MARK: - Dynamic resolution

    /// The content accent must be a *dynamic* colour. Flattening it once at
    /// read time would leave every accent-coloured label wrong after an
    /// appearance change.
    @Test
    func contentAccentResolvesPerAppearance() {
        for accent in AccentColor.allCases {
            let light = accent.contentColor.resolvedColor(with: Self.traits(.light))
            let dark = accent.contentColor.resolvedColor(with: Self.traits(.dark))
            #expect(light != dark, "\(accent.rawValue) content accent resolves identically in light and dark")
        }
    }

    /// `ThemeManager` hands out the content variant of whatever accent is
    /// currently applied — the fill and the content value can never come from
    /// different accents.
    @Test
    @MainActor
    func themeManagerPublishesTheMatchingContentAccent() {
        let manager = ThemeManager.shared
        let original = manager.accent
        defer { manager.setAccent(original) }

        for accent in AccentColor.allCases {
            manager.setAccent(accent)
            for style in Self.styles {
                let traits = Self.traits(style)
                #expect(
                    ThemeManager.currentAccentColor.resolvedColor(with: traits)
                        == accent.color.resolvedColor(with: traits)
                )
                #expect(
                    ThemeManager.currentContentAccentColor.resolvedColor(with: traits)
                        == accent.contentColor.resolvedColor(with: traits)
                )
            }
        }
    }
}
