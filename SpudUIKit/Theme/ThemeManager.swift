//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

/// Process-wide holder of the resolved appearance: the active ``AppTheme``
/// and ``AccentColor``.
///
/// The scene/window layer is responsible for two things on every change:
///  1. setting each window's `overrideUserInterfaceStyle`, and
///  2. setting each window's `tintColor` to the accent.
/// Updating `current` here keeps the color providers in sync with both.
@MainActor
public final class ThemeManager {
    public static let shared = ThemeManager()

    /// The currently-applied theme. Defaults to `.system` until the
    /// preferences layer pushes the persisted value.
    public private(set) var theme: AppTheme = .system

    /// The currently-applied accent. Defaults to `.lemmy`.
    public private(set) var accent: AccentColor = .lemmy

    /// Thread-safe mirror of the active accent's resolved `UIColor`, readable
    /// from non-isolated color resolvers — the vote tints in `GeneralAppearance`
    /// follow the accent without hopping actors.
    private nonisolated static let accentColorBox = AccentColorBox()

    /// Non-isolated read of the current accent color. Safe from any thread.
    public nonisolated static var currentAccentColor: UIColor {
        accentColorBox.value
    }

    private init() { }

    /// Updates the active theme. The caller (scene/window layer) is
    /// responsible for re-applying `overrideUserInterfaceStyle` so UIKit
    /// re-resolves the dynamic colors.
    public func setTheme(_ theme: AppTheme) {
        self.theme = theme
    }

    /// Updates the active accent. The caller (scene/window layer) is
    /// responsible for re-applying `window.tintColor`.
    public func setAccent(_ accent: AccentColor) {
        self.accent = accent
        Self.accentColorBox.value = accent.color
    }
}

/// A tiny lock-guarded accent color, safe to read from any thread. Seeded with
/// the default accent until the preferences layer pushes the persisted value.
private final class AccentColorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: UIColor = AccentColor.lemmy.color

    var value: UIColor {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            _value = newValue
            lock.unlock()
        }
    }
}
