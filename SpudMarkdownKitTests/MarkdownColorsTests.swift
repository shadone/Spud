//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import XCTest
@testable import SpudMarkdownKit

final class MarkdownColorsTests: XCTestCase {
    func test_inlineCodeForegroundResolvesLightAndDark() {
        let light = MarkdownColors.inlineCodeForeground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light)
        )
        let dark = MarkdownColors.inlineCodeForeground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .dark)
        )
        XCTAssertNotEqual(light, dark)
    }

    func test_highlightIsTranslucentYellow() {
        var alpha: CGFloat = 0
        MarkdownColors.highlight.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getRed(nil, green: nil, blue: nil, alpha: &alpha)
        XCTAssertLessThan(alpha, 1.0)
        XCTAssertGreaterThan(alpha, 0.0)
    }
}
