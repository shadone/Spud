//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A user-selectable app icon.
///
/// `.default` is the primary icon shipped in the asset catalog
/// (`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`); selecting it calls
/// `setAlternateIconName(nil)`. Every other case is a loose-PNG alternate icon
/// declared under `CFBundleIcons` → `CFBundleAlternateIcons` in `Info.plist`,
/// whose ``alternateIconName`` is the key UIKit expects in
/// `setAlternateIconName(_:)` (it resolves the bundle-root `AppIcon-<Name>@Nx.png`
/// files automatically).
///
/// These are placeholder variations on the "potato" motif, to be replaced with
/// final art later.
public enum AppIconVariant: String, CaseIterable, Identifiable, Sendable {
    case `default`
    case midnight
    case forest
    case sunset
    case mono

    public var id: String {
        rawValue
    }

    /// The name to pass to `UIApplication.setAlternateIconName(_:)`. `nil`
    /// restores the primary asset-catalog icon.
    public var alternateIconName: String? {
        switch self {
        case .default:
            return nil
        case .midnight:
            return "Midnight"
        case .forest:
            return "Forest"
        case .sunset:
            return "Sunset"
        case .mono:
            return "Mono"
        }
    }

    /// Human-readable name for the picker.
    public var title: String {
        switch self {
        case .default:
            return "Potato"
        case .midnight:
            return "Midnight"
        case .forest:
            return "Forest"
        case .sunset:
            return "Sunset"
        case .mono:
            return "Mono"
        }
    }

    /// Asset-catalog image name for the picker preview swatch (a 1024 render
    /// bundled as an imageset). These live in the app's main asset catalog.
    public var previewImageName: String {
        switch self {
        case .default:
            return "AppIconPreview-Default"
        case .midnight:
            return "AppIconPreview-Midnight"
        case .forest:
            return "AppIconPreview-Forest"
        case .sunset:
            return "AppIconPreview-Sunset"
        case .mono:
            return "AppIconPreview-Mono"
        }
    }

    /// Resolves the currently applied icon from UIKit's
    /// `alternateIconName`. `nil` (no alternate set) maps to `.default`.
    @MainActor
    public static func current(alternateIconName: String?) -> AppIconVariant {
        guard let alternateIconName else { return .default }
        return allCases.first { $0.alternateIconName == alternateIconName } ?? .default
    }
}
