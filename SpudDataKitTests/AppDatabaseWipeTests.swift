//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

/// Guards ``AppDatabase/wipePersistentStore(at:)`` — the DEBUG UI-test seam that
/// deletes the on-disk database directory so a test run starts from a truly
/// fresh install (the App Group database survives SBT's ResetFilesystem and
/// `simctl uninstall`, so a persisted account otherwise makes the launch seeds
/// no-op).
///
/// These tests drive the internal, directory-parameterized form against a temp
/// directory; they never touch the real App Group container of the test host.
struct AppDatabaseWipeTests {
    @Test
    func deletesExistingDirectoryWithDatabaseFile() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory
            .appendingPathComponent("AppDatabaseWipe-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }

        // Simulate the on-disk store: the SQLite file plus its WAL/SHM sidecars.
        for name in ["AppDatabase.sqlite", "AppDatabase.sqlite-wal", "AppDatabase.sqlite-shm"] {
            try Data("x".utf8).write(to: directory.appendingPathComponent(name))
        }
        #expect(fm.fileExists(atPath: directory.path))

        AppDatabase.wipePersistentStore(at: directory)

        #expect(
            !fm.fileExists(atPath: directory.path),
            "The whole database directory (file + WAL/SHM) should be gone after a wipe"
        )
    }

    @Test
    func noOpsCleanlyWhenDirectoryAbsent() {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory
            .appendingPathComponent("AppDatabaseWipe-absent-\(UUID().uuidString)", isDirectory: true)
        #expect(!fm.fileExists(atPath: directory.path))

        // Must not throw or crash when there is nothing to delete.
        AppDatabase.wipePersistentStore(at: directory)

        #expect(!fm.fileExists(atPath: directory.path))
    }
}
