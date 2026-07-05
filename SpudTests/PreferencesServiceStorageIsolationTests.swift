//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUIKit
import Testing
@testable import Spud

/// `PreferencesService` gained an injectable `UserDefaults` store so tests can
/// run against a private, disposable suite instead of the shared
/// `UserDefaults.standard` (`info.ddenis.Spud`) domain that leaks between the
/// hosted `SpudTests` process and later `SpudUITests` launches.
///
/// Test 3 deliberately writes to `.standard` to prove the default initializer
/// still reads/writes it; it mutates exactly ONE key and restores it in a
/// `defer`, following the `QuickSwitchViewModelTests` pattern. (Constructing
/// any `PreferencesService`, including a default-init one, also runs the
/// xcancel -> sanitizer migration, which idempotently writes
/// `didMigrateXcancelToSanitizer` to its store — so Test 3's actual
/// `.standard` footprint is that flag plus the one deliberately-mutated key.)
/// The suite is `.serialized` because Swift Testing runs a struct's `@Test`
/// funcs in parallel by default and Test 3 mutates the shared `.standard`
/// domain.
@MainActor
@Suite(.serialized)
struct PreferencesServiceStorageIsolationTests {
    /// Two services built on distinct injected suites do not observe each
    /// other's writes, and untouched properties read their documented defaults.
    @Test
    func injectedStores_areIsolated() throws {
        let a = try PreferencesService(storage: #require(UserDefaults(suiteName: "test-\(UUID().uuidString)")))
        let b = try PreferencesService(storage: #require(UserDefaults(suiteName: "test-\(UUID().uuidString)")))

        a.showVoteButtons = false

        #expect(b.showVoteButtons == true) // default, not a's write
        #expect(a.thumbnailPosition == .left) // untouched props read defaults
    }

    /// Mutating an injected-store service never writes through to
    /// `UserDefaults.standard`.
    @Test
    func injectedStore_neverTouchesStandard() throws {
        let service = try PreferencesService(storage: #require(UserDefaults(suiteName: "test-\(UUID().uuidString)")))

        let keys = ["showNsfw", "hideReadPosts", "postTextScale"]
        let before = keys.map { UserDefaults.standard.string(forKey: $0) }

        // Write non-default values through the injected store.
        service.showNsfw = true
        service.hideReadPosts = true
        service.postTextScale = 7

        let after = keys.map { UserDefaults.standard.string(forKey: $0) }
        #expect(before == after)
    }

    /// The default initializer still reads/writes `UserDefaults.standard`:
    /// a write through one default-init instance is visible to another.
    @Test
    func defaultInit_readsStandard() {
        let key = "markPostsReadOnScroll"
        let original = UserDefaults.standard.string(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let writer = PreferencesService()
        writer.markPostsReadOnScroll = true // default is false

        let reader = PreferencesService()
        #expect(reader.markPostsReadOnScroll == true)
    }
}
