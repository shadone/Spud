//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import XCTest
@testable import SpudUIKit

final class ThemeResolutionTests: XCTestCase {
    // MARK: AppTheme -> UIUserInterfaceStyle

    func test_appTheme_userInterfaceStyle() {
        XCTAssertEqual(AppTheme.system.userInterfaceStyle, .unspecified)
        XCTAssertEqual(AppTheme.light.userInterfaceStyle, .light)
        XCTAssertEqual(AppTheme.dark.userInterfaceStyle, .dark)
        // True Black is a dark variant — same interface style as Dark.
        XCTAssertEqual(AppTheme.trueBlack.userInterfaceStyle, .dark)
    }

    func test_appTheme_usesTrueBlackBackgrounds() {
        XCTAssertFalse(AppTheme.system.usesTrueBlackBackgrounds)
        XCTAssertFalse(AppTheme.light.usesTrueBlackBackgrounds)
        XCTAssertFalse(AppTheme.dark.usesTrueBlackBackgrounds)
        XCTAssertTrue(AppTheme.trueBlack.usesTrueBlackBackgrounds)
    }

    func test_appTheme_roundTripsThroughRawValue() {
        for theme in AppTheme.allCases {
            XCTAssertEqual(AppTheme(rawValue: theme.rawValue), theme)
        }
    }

    // MARK: AccentColor -> UIColor

    func test_accentColor_lemmyIsTheBrandTeal() {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        AccentColor.lemmy.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 0.0, accuracy: 0.01)
        XCTAssertEqual(green, 0.59, accuracy: 0.01)
        XCTAssertEqual(blue, 0.53, accuracy: 0.01)
        XCTAssertEqual(alpha, 1.0, accuracy: 0.01)
    }

    func test_accentColor_distinctColorsPerCase() {
        // Each accent should resolve to a distinct concrete color in the
        // light trait environment.
        let light = UITraitCollection(userInterfaceStyle: .light)
        let resolved = AccentColor.allCases.map { $0.color.resolvedColor(with: light) }
        for (lhsIndex, lhs) in resolved.enumerated() {
            for rhs in resolved[(lhsIndex + 1)...] {
                XCTAssertNotEqual(lhs, rhs)
            }
        }
    }

    func test_accentColor_roundTripsThroughRawValue() {
        for accent in AccentColor.allCases {
            XCTAssertEqual(AccentColor(rawValue: accent.rawValue), accent)
        }
    }

    func test_accentColor_defaultIsLemmy() {
        XCTAssertEqual(AccentColor.allCases.first, .lemmy)
    }
}
