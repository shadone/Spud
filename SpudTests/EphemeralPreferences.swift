//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
@testable import Spud

extension PreferencesService {
    /// A `PreferencesService` backed by a fresh, private `UserDefaults` suite so
    /// a test never reads from — or writes to — the shared `.standard`
    /// (`info.ddenis.Spud`) domain. `SpudTests` is hosted inside the `Spud` app
    /// target, so `.standard` is the same domain a later `SpudUITests` launch
    /// reads from, and `ResetFilesystem` does not reliably clear it. Each call
    /// gets a unique suite, so `@Test` funcs stay isolated even when Swift
    /// Testing runs them in parallel — no `.serialized` and no `defer`-restore
    /// of mutated keys is needed.
    @MainActor
    static func ephemeral() -> PreferencesService {
        PreferencesService(storage: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }
}
