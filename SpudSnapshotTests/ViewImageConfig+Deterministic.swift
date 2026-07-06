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
    ///
    /// NOTE: this does NOT also pin `preferredContentSizeCategory` the way
    /// `SnapshotDeterminism.contentSizeTrait` does for the `.image(size:traits:)`
    /// family — `.iPhone13Pro`'s base trait collection already bakes
    /// `preferredContentSizeCategory: .medium` (see swift-snapshot-testing's
    /// `UITraitCollection.iPhone13`), which every existing ref in this family was
    /// recorded under. Probed 2026-07-06: merging `.large` in here measurably
    /// changes rendered text size and breaks existing refs (e.g.
    /// `LoginScreenSnapshotTests`), so this family is intentionally left as-is;
    /// it is not exposed to the sim-level Dynamic Type pollution
    /// `contentSizeTrait` guards against because its base config already fully
    /// specifies the trait, sim state or not.
    static var deterministicPhone: ViewImageConfig {
        var config = ViewImageConfig.iPhone13Pro
        config.safeArea = .zero
        return config
    }

    /// `.iPadPro11(.landscape)`'s size and traits, but with the safe area pinned to
    /// `.zero` — the iPad-landscape analog of ``deterministicPhone``.
    ///
    /// Same rationale: `.iPadPro11(.landscape)` carries a non-zero device safe area
    /// whose installation drifted across swift-snapshot-testing versions, shifting
    /// every VC-hosted capture, and its non-zero safe area routes the render through
    /// the on-screen key-window path where a prior suite can contaminate it. Pinning
    /// `.zero` forces the deterministic fully-off-screen path while keeping the wide
    /// iPad canvas, so the iPad-adaptive-layout assertions (grid rails, capped
    /// directory column) still render at their real regular-size-class width.
    ///
    /// Same NOTE as ``deterministicPhone`` re `preferredContentSizeCategory`:
    /// left unpinned here for the same reason (the base `.iPadPro11` trait
    /// already fully specifies it, and forcing `.large` measurably changes
    /// existing refs).
    static var deterministicIPadLandscape: ViewImageConfig {
        var config = ViewImageConfig.iPadPro11(.landscape)
        config.safeArea = .zero
        return config
    }
}
