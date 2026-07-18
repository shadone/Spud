//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Fire-and-forget access point for the scattered one-line fun-stat hooks
/// (scroll deltas, taps, opens). Installed once at app startup; while
/// uninstalled (unit tests, previews, extensions) every call is a no-op.
///
/// Deliberately NOT the `Has*Service` DI pattern: threading `HasStatsService`
/// through a dozen scene `Dependencies` typealiases would cascade into every
/// manually-spelled `NestedDependencies` and every test double (see CLAUDE.md
/// on Dependencies cascades) for hooks that have no behavioral coupling to
/// their host screens. Structural consumers (DependencyContainer,
/// SceneDelegate, the Fun Stats screen) still receive `StatsServicing` via DI.
public enum FunStats {
    @MainActor private static var backend: StatsServicing?

    /// Installs (or, with nil, removes) the process-wide recording backend.
    @MainActor
    public static func install(_ backend: StatsServicing?) {
        self.backend = backend
    }

    /// Records `amount` into `key` via the installed backend; no-op when
    /// nothing is installed. Safe to call from any MainActor context at any
    /// frequency worth counting (taps, batched scroll deltas).
    @MainActor
    public static func record(_ key: FunStatKey, amount: Double = 1) {
        guard let backend else { return }
        Task {
            await backend.record(key, amount: amount)
        }
    }
}
