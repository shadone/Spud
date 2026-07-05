//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import Testing
import UIKit
@testable import Spud

@MainActor
struct VoteFillStyleTests {
    private func appearance() -> GeneralAppearance {
        GeneralAppearance()
    }

    @Test
    func upResolvesToAccent() {
        let fill = VoteFillStyle.fillColor(for: .up, appearance: appearance())
        #expect(fill == ThemeManager.currentAccentColor)
    }

    @Test
    func downResolvesToDownToken() {
        let fill = VoteFillStyle.fillColor(for: .down, appearance: appearance())
        #expect(fill == GeneralAppearance.downColor)
    }

    @Test
    func neutralHasNoFill() {
        #expect(VoteFillStyle.fillColor(for: .neutral, appearance: appearance()) == nil)
    }

    @Test
    func filledGlyphIsWhite() {
        #expect(VoteFillStyle.filledGlyphColor == .white)
    }
}
