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
/// The theme-aware `UIColor` providers in ``Theme`` read `shared` at draw
/// time, so when the active theme changes, any view that asks UIKit to
/// re-resolve its dynamic colors (which happens automatically on a
/// trait-collection change, e.g. when a window's `overrideUserInterfaceStyle`
/// flips) picks up the new background. The True-Black swap is therefore
/// driven entirely from this one place rather than scattered overrides.
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

    /// Thread-safe mirror of `theme.usesTrueBlackBackgrounds`, readable from
    /// the dynamic `UIColor` provider closures in ``Theme`` (UIKit may resolve
    /// dynamic colors off the main thread, so they must not touch the
    /// MainActor-isolated `theme` directly).
    private nonisolated static let trueBlackFlag = TrueBlackFlag()

    /// Non-isolated read of whether True-Black backgrounds are active. Safe
    /// to call from any thread.
    public nonisolated static var usesTrueBlackBackgrounds: Bool {
        trueBlackFlag.value
    }

    private init() { }

    /// Updates the active theme. The caller (scene/window layer) is
    /// responsible for re-applying `overrideUserInterfaceStyle` so UIKit
    /// re-resolves the dynamic colors that read the True-Black flag.
    public func setTheme(_ theme: AppTheme) {
        self.theme = theme
        Self.trueBlackFlag.value = theme.usesTrueBlackBackgrounds
    }

    /// Updates the active accent. The caller (scene/window layer) is
    /// responsible for re-applying `window.tintColor`.
    public func setAccent(_ accent: AccentColor) {
        self.accent = accent
    }
}

/// A tiny lock-guarded boolean, safe to read from any thread (including the
/// background threads UIKit may use to resolve dynamic colors).
private final class TrueBlackFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    var value: Bool {
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
