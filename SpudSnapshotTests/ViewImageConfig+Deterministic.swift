//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit

extension ViewImageConfig {
    /// `.iPhone13Pro`'s size and traits, but with the safe area pinned to `.zero`.
    ///
    /// This is the deterministic replacement for `.iPhone13Pro` in view-controller
    /// snapshots. Two independent nondeterminism sources plague the stock
    /// `.image(on: .iPhone13Pro)` path, and a zero safe area removes both at once:
    ///
    /// 1. **Library/runtime safe-area drift.** `.iPhone13Pro` carries a non-zero
    ///    device safe area (47pt top / 34pt bottom). How swift-snapshot-testing
    ///    installs that inset changed between versions, shifting every VC-hosted
    ///    capture ~44pt vertically — so a recorded reference silently stopped
    ///    matching a fresh render even with no app change. An explicit `.zero`
    ///    pins the layout regardless of the library's device handling.
    /// 2. **Cross-suite key-window contamination.** The library renders a
    ///    controller *fully off-screen* (no key window) precisely when
    ///    `config.safeArea == .zero` (see its `snapshotView`); with a non-zero
    ///    safe area it falls back to an on-screen path whose result depends on the
    ///    ambient key window a prior suite in the same process can perturb.
    ///
    /// The render stays device-independent (fixed size, off-screen), so these
    /// snapshots still record and verify on any simulator. Content lays out from
    /// the top with no safe-area gap; references recorded with this reflect that.
    ///
    /// For captures that genuinely need an on-screen render (a `UIVisualEffectView`
    /// blur, SwiftUI `.task`-driven content), use ``FixedSafeAreaWindow`` with
    /// `drawHierarchyInKeyWindow: true` instead — it pins the key window's safe
    /// area to the same `.zero` on the on-screen path.
    static var deterministicPhone: ViewImageConfig {
        var config = ViewImageConfig.iPhone13Pro
        config.safeArea = .zero
        return config
    }
}
