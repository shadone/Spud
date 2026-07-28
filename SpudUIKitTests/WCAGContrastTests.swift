//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
import UIKit
@testable import SpudUIKit

/// Validates ``WCAGContrast`` against values fixed by the WCAG 2.x definitions
/// themselves, so an accessibility assertion elsewhere in the app is standing on
/// arithmetic that has been checked rather than eyeballed.
struct WCAGContrastTests {
    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    // MARK: - Relative luminance

    @Test
    func luminanceOfBlackIsZeroAndWhiteIsOne() {
        #expect(WCAGContrast.relativeLuminance(red: 0, green: 0, blue: 0) == 0)
        #expect(abs(WCAGContrast.relativeLuminance(red: 1, green: 1, blue: 1) - 1) < 1e-9)
    }

    /// The primaries carry exactly the coefficients from the definition.
    @Test
    func luminanceOfThePrimariesMatchesTheCoefficients() {
        #expect(abs(WCAGContrast.relativeLuminance(red: 1, green: 0, blue: 0) - 0.2126) < 1e-9)
        #expect(abs(WCAGContrast.relativeLuminance(red: 0, green: 1, blue: 0) - 0.7152) < 1e-9)
        #expect(abs(WCAGContrast.relativeLuminance(red: 0, green: 0, blue: 1) - 0.0722) < 1e-9)
    }

    /// The sRGB transfer function is piecewise: below 0.04045 it is a plain
    /// division by 12.92, above it a 2.4 power. An approximate 2.2 gamma gets
    /// the dark end wrong by enough to move a borderline ratio across AA.
    @Test
    func luminanceUsesThePiecewiseSRGBTransferFunction() {
        // Just inside the linear segment: 0.04 / 12.92.
        let linearSegment = WCAGContrast.relativeLuminance(red: 0.04, green: 0.04, blue: 0.04)
        #expect(abs(linearSegment - 0.04 / 12.92) < 1e-9)

        // Mid grey (128/255) is the canonical worked example: 0.2158.
        let midGrey = WCAGContrast.relativeLuminance(red: 128.0 / 255, green: 128.0 / 255, blue: 128.0 / 255)
        #expect(abs(midGrey - 0.2158) < 0.0005)

        // A 2.2-power approximation would give ~0.2176 here; make sure we are
        // not accidentally that.
        #expect(abs(midGrey - pow(128.0 / 255, 2.2)) > 0.001)
    }

    @Test
    func luminanceClampsOutOfRangeComponents() {
        #expect(WCAGContrast.relativeLuminance(red: -0.5, green: -0.5, blue: -0.5) == 0)
        #expect(abs(WCAGContrast.relativeLuminance(red: 1.4, green: 1.4, blue: 1.4) - 1) < 1e-9)
    }

    // MARK: - Contrast ratio

    @Test
    func blackOnWhiteIsTheMaximumRatio() {
        let ratio = WCAGContrast.ratio(between: .black, and: .white, in: light)
        #expect(abs(ratio - 21) < 1e-6)
    }

    @Test
    func aColourAgainstItselfIsOne() {
        #expect(abs(WCAGContrast.ratio(between: .systemTeal, and: .systemTeal, in: light) - 1) < 1e-9)
    }

    @Test
    func ratioIsSymmetric() {
        let forward = WCAGContrast.ratio(between: .black, and: .systemOrange, in: light)
        let backward = WCAGContrast.ratio(between: .systemOrange, and: .black, in: light)
        #expect(abs(forward - backward) < 1e-12)
    }

    /// #767676 on white is the canonical "smallest grey that passes AA" — it is
    /// the value accessibility guidance quotes as 4.54:1.
    @Test
    func theCanonicalAAGreyMeasuresJustOverFourAndAHalf() {
        let grey = UIColor(red: 0x76 / 255, green: 0x76 / 255, blue: 0x76 / 255, alpha: 1)
        let ratio = WCAGContrast.ratio(between: grey, and: .white, in: light)
        #expect(ratio >= WCAGContrast.aaNormalText)
        #expect(abs(ratio - 4.54) < 0.02)
    }

    /// One shade lighter fails, so the threshold is genuinely discriminating.
    @Test
    func oneShadeLighterThanTheCanonicalGreyFailsAA() {
        let grey = UIColor(red: 0x77 / 255, green: 0x77 / 255, blue: 0x77 / 255, alpha: 1)
        #expect(WCAGContrast.ratio(between: grey, and: .white, in: light) < WCAGContrast.aaNormalText)
    }

    // MARK: - Dynamic colours

    /// A dynamic colour is resolved per trait collection, so light and dark can
    /// be measured independently — the whole point of taking a trait argument.
    @Test
    func dynamicColoursResolvePerTraitCollection() {
        let inLight = WCAGContrast.relativeLuminance(of: .label, in: light)
        let inDark = WCAGContrast.relativeLuminance(of: .label, in: dark)
        #expect(inLight < 0.05, "`.label` is near-black in light")
        #expect(inDark > 0.8, "`.label` is near-white in dark")

        // And it pairs with the matching background at close to the maximum in
        // both appearances - this is exactly the pairing the jump FAB relies on.
        #expect(WCAGContrast.ratio(between: .label, and: .systemBackground, in: light) > 15)
        #expect(WCAGContrast.ratio(between: .label, and: .systemBackground, in: dark) > 15)
    }

    /// Alpha is ignored rather than silently composited against an assumed
    /// backdrop, which would produce a confidently wrong number.
    @Test
    func alphaIsIgnored() {
        let opaque = WCAGContrast.relativeLuminance(of: .black, in: light)
        let translucent = WCAGContrast.relativeLuminance(of: UIColor.black.withAlphaComponent(0.1), in: light)
        #expect(opaque == translucent)
    }

    // MARK: - Thresholds

    @Test
    func thresholdsMatchTheSuccessCriteria() {
        #expect(WCAGContrast.aaNormalText == 4.5)
        #expect(WCAGContrast.aaLargeText == 3.0)
        #expect(WCAGContrast.aaNonText == 3.0)
    }
}
