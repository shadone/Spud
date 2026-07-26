//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The user-selectable app appearance.
///
/// Each case maps directly onto a `UIUserInterfaceStyle`.
public enum AppTheme: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case light
    case dark

    public var id: String {
        rawValue
    }

    /// The interface style UIKit should apply for this theme.
    public var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system:
            return .unspecified
        case .light:
            return .light
        case .dark:
            return .dark
        }
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
        }
    }

    /// Legacy raw value of the retired True Black (OLED) theme.
    private static let retiredTrueBlackRawValue = "trueBlack"

    /// Decodes a persisted selection, mapping the retired True Black theme
    /// onto `.dark`.
    ///
    /// True Black existed only to force opaque bars on OLED displays; Liquid
    /// Glass replaces that chrome entirely, so the theme was retired. Without
    /// this mapping `UserDefaultsBacked` would fail to decode the stored value
    /// and silently fall back to `.system`, discarding the user's dark-mode
    /// choice along with their OLED preference.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        if rawValue == Self.retiredTrueBlackRawValue {
            self = .dark
            return
        }

        guard let theme = AppTheme(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised AppTheme raw value '\(rawValue)'"
            )
        }
        self = theme
    }
}
