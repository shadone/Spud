//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The user-selectable app appearance.
///
/// `.system`, `.light`, and `.dark` map directly onto a
/// `UIUserInterfaceStyle`. `.trueBlack` is a dark variant that additionally
/// swaps the app's background tokens to pure black for OLED displays — the
/// interface style is still `.dark`, but ``Theme/usesTrueBlackBackgrounds``
/// is `true`, which the theme-aware color providers honour.
public enum AppTheme: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case light
    case dark
    case trueBlack

    public var id: String {
        rawValue
    }

    /// The interface style UIKit should apply for this theme. `.trueBlack`
    /// resolves to `.dark`; the pure-black swap is layered on top of dark
    /// mode by the color providers.
    public var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system:
            return .unspecified
        case .light:
            return .light
        case .dark, .trueBlack:
            return .dark
        }
    }

    /// Whether this theme replaces the standard dark backgrounds with pure
    /// black. Only `.trueBlack` does.
    public var usesTrueBlackBackgrounds: Bool {
        self == .trueBlack
    }

    /// Human-readable name for the settings picker.
    public var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        case .trueBlack:
            return "True Black"
        }
    }

    /// SF Symbol name representing this theme in the settings picker.
    public var symbolName: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        case .trueBlack:
            return "moon.stars.fill"
        }
    }
}
