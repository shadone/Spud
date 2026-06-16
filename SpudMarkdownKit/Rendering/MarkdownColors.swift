//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// The non-system colors the markdown design uses, as dynamic colors that
/// resolve light/dark at draw time.
enum MarkdownColors {
    /// Inline-code text: a warm brown (light) / soft peach (dark).
    static let inlineCodeForeground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xE8 / 255, green: 0xB9 / 255, blue: 0xA0 / 255, alpha: 1)
            : UIColor(red: 0x9A / 255, green: 0x4A / 255, blue: 0x25 / 255, alpha: 1)
    }

    /// ==highlight== background — translucent yellow.
    static let highlight = UIColor { traits in
        UIColor.systemYellow.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.26 : 0.34)
    }

    /// Tinted chip background for @mentions / !communities — the accent at low alpha.
    static var chipBackground: UIColor {
        UIColor { _ in ThemeManager.currentAccentColor.withAlphaComponent(0.15) }
    }
}
