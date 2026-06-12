//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Theme-aware semantic color tokens.
///
/// These are the colors the app should use for surfaces that need to go pure
/// black under the True-Black (OLED) theme. Each is a dynamic `UIColor` whose
/// provider closure is consulted by UIKit every time the color is resolved
/// against a trait collection. In a dark trait collection we additionally
/// check ``ThemeManager/theme`` — when True-Black is active we return black
/// instead of the standard system background, while light mode and ordinary
/// dark mode fall straight through to the system color.
///
/// Because resolution happens lazily at draw time, flipping a window's
/// `overrideUserInterfaceStyle` (which the scene layer does on a theme change)
/// triggers a trait-collection change that re-resolves every dynamic color —
/// so tables, cells, nav bars and tab bars all pick up the OLED swap with no
/// per-view override code.
public enum Theme {
    /// True black, used for OLED backgrounds.
    public static let trueBlack = UIColor.black

    /// Theme-aware replacement for `UIColor.systemBackground`. Pure black
    /// when the True-Black theme is active and the trait collection is dark.
    public static let background = dynamic(
        standard: .systemBackground,
        trueBlackDark: trueBlack
    )

    /// Theme-aware replacement for `UIColor.secondarySystemBackground`.
    public static let secondaryBackground = dynamic(
        standard: .secondarySystemBackground,
        trueBlackDark: trueBlack
    )

    /// Theme-aware replacement for `UIColor.tertiarySystemBackground`.
    public static let tertiaryBackground = dynamic(
        standard: .tertiarySystemBackground,
        trueBlackDark: trueBlack
    )

    /// Theme-aware replacement for `UIColor.systemGroupedBackground`.
    public static let groupedBackground = dynamic(
        standard: .systemGroupedBackground,
        trueBlackDark: trueBlack
    )

    /// Theme-aware replacement for `UIColor.secondarySystemGroupedBackground`
    /// (the color of cells inside a grouped table). Under True-Black we lift
    /// it slightly off pure black so cells stay distinguishable from the
    /// black grouped background behind them.
    public static let secondaryGroupedBackground = dynamic(
        standard: .secondarySystemGroupedBackground,
        trueBlackDark: UIColor(white: 0.07, alpha: 1.0)
    )

    /// Builds a dynamic color that returns `trueBlackDark` when the trait
    /// collection is dark *and* the True-Black theme is active, otherwise
    /// `standard` (which is itself usually a dynamic system color that adapts
    /// to light/dark on its own).
    private static func dynamic(
        standard: UIColor,
        trueBlackDark: UIColor
    ) -> UIColor {
        UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark,
               ThemeManager.usesTrueBlackBackgrounds
            {
                return trueBlackDark.resolvedColor(with: traitCollection)
            }
            return standard.resolvedColor(with: traitCollection)
        }
    }
}
