//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Theme-aware semantic color tokens.
///
/// The True Black (OLED) theme that used to swap these to pure black has
/// been retired (Liquid Glass replaces the opaque chrome it existed for), so
/// every token below now simply passes its `standard` system color through
/// unchanged. The type is kept alive as a stable seam for call sites; Task 4
/// removes it and its ~68 call sites entirely.
public enum Theme {
    /// True black, used for OLED backgrounds.
    public static let trueBlack = UIColor.black

    /// Theme-aware replacement for `UIColor.systemBackground`.
    public static let background = dynamic(standard: .systemBackground)

    /// Theme-aware replacement for `UIColor.secondarySystemBackground`.
    public static let secondaryBackground = dynamic(standard: .secondarySystemBackground)

    /// Theme-aware replacement for `UIColor.tertiarySystemBackground`.
    public static let tertiaryBackground = dynamic(standard: .tertiarySystemBackground)

    /// Theme-aware replacement for `UIColor.systemGroupedBackground`.
    public static let groupedBackground = dynamic(standard: .systemGroupedBackground)

    /// Theme-aware replacement for `UIColor.secondarySystemGroupedBackground`
    /// (the color of cells inside a grouped table).
    public static let secondaryGroupedBackground = dynamic(standard: .secondarySystemGroupedBackground)

    /// Returns `standard` unchanged. Retained as a seam so every token above
    /// keeps its existing shape until Task 4 deletes this type outright.
    private static func dynamic(standard: UIColor) -> UIColor {
        standard
    }
}
