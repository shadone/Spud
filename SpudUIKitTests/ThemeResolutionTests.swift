//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
import UIKit
@testable import SpudUIKit

struct ThemeResolutionTests {
    // MARK: AppTheme -> UIUserInterfaceStyle

    @Test
    func appTheme_userInterfaceStyle() {
        #expect(AppTheme.system.userInterfaceStyle == .unspecified)
        #expect(AppTheme.light.userInterfaceStyle == .light)
        #expect(AppTheme.dark.userInterfaceStyle == .dark)
        // True Black is a dark variant — same interface style as Dark.
        #expect(AppTheme.trueBlack.userInterfaceStyle == .dark)
    }

    @Test
    func appTheme_usesTrueBlackBackgrounds() {
        #expect(!AppTheme.system.usesTrueBlackBackgrounds)
        #expect(!AppTheme.light.usesTrueBlackBackgrounds)
        #expect(!AppTheme.dark.usesTrueBlackBackgrounds)
        #expect(AppTheme.trueBlack.usesTrueBlackBackgrounds)
    }

    @Test
    func appTheme_roundTripsThroughRawValue() {
        for theme in AppTheme.allCases {
            #expect(AppTheme(rawValue: theme.rawValue) == theme)
        }
    }

    // MARK: AccentColor -> UIColor

    @Test
    func accentColor_lemmyIsTheBrandTeal() {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        AccentColor.lemmy.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(abs(red - 0.0) <= 0.01)
        #expect(abs(green - 0.59) <= 0.01)
        #expect(abs(blue - 0.53) <= 0.01)
        #expect(abs(alpha - 1.0) <= 0.01)
    }

    @Test
    func accentColor_distinctColorsPerCase() {
        // Each accent should resolve to a distinct concrete color in the
        // light trait environment.
        let light = UITraitCollection(userInterfaceStyle: .light)
        let resolved = AccentColor.allCases.map { $0.color.resolvedColor(with: light) }
        for (lhsIndex, lhs) in resolved.enumerated() {
            for rhs in resolved[(lhsIndex + 1)...] {
                #expect(lhs != rhs)
            }
        }
    }

    @Test
    func accentColor_roundTripsThroughRawValue() {
        for accent in AccentColor.allCases {
            #expect(AccentColor(rawValue: accent.rawValue) == accent)
        }
    }

    @Test
    func accentColor_defaultIsLemmy() {
        #expect(AccentColor.allCases.first == .lemmy)
    }
}
