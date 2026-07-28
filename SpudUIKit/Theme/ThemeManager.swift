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
    ///
    /// This is the **fill** accent — the vivid swatch, for surfaces the accent
    /// paints. When the accent is drawn as text or as a meaningful glyph, read
    /// ``currentContentAccentColor`` instead.
    public nonisolated static var currentAccentColor: UIColor {
        accentColorBox.value
    }

    /// Non-isolated read of the current accent's **content** variant — the
    /// luminance-corrected value for accent-coloured text and glyphs. Safe from
    /// any thread.
    ///
    /// A dynamic colour: it resolves Light and Dark separately, so it stays
    /// correct across an appearance change. Derived once per accent change (the
    /// derivation is a bisection, not something to run per cell).
    public nonisolated static var currentContentAccentColor: UIColor {
        accentColorBox.contentValue
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
        Self.accentColorBox.set(fill: accent.color, content: accent.contentColor)
    }
}

/// A tiny lock-guarded accent color pair — the vivid fill and its
/// luminance-corrected content variant — safe to read from any thread. Seeded
/// with the default accent until the preferences layer pushes the persisted
/// value.
///
/// The pair is stored together, and written together, so a reader can never
/// observe a content variant derived from a *different* accent than the fill it
/// sits next to.
private final class AccentColorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: UIColor = AccentColor.lemmy.color
    private var _contentValue: UIColor = AccentColor.lemmy.contentColor

    var value: UIColor {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    var contentValue: UIColor {
        lock.lock()
        defer { lock.unlock() }
        return _contentValue
    }

    func set(fill: UIColor, content: UIColor) {
        lock.lock()
        _value = fill
        _contentValue = content
        lock.unlock()
    }
}
