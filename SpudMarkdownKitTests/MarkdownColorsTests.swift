//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
import UIKit
@testable import SpudMarkdownKit

struct MarkdownColorsTests {
    @Test
    func inlineCodeForegroundResolvesLightAndDark() {
        let light = MarkdownColors.inlineCodeForeground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light)
        )
        let dark = MarkdownColors.inlineCodeForeground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .dark)
        )
        #expect(light != dark)
    }

    @Test
    func highlightIsTranslucentYellow() {
        var alpha: CGFloat = 0
        MarkdownColors.highlight.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getRed(nil, green: nil, blue: nil, alpha: &alpha)
        #expect(alpha < 1.0)
        #expect(alpha > 0.0)
    }
}
