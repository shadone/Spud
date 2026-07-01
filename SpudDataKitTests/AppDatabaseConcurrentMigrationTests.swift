//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

/// Guards the cross-process migration lock in ``AppDatabase``.
///
/// Two independent connections opening and migrating the SAME fresh on-disk
/// database concurrently must both succeed. Without the lock this is the exact
/// race that crashed TestFlight build 24 at launch: the app and its widget each
/// ran GRDB's migrator against the shared App Group database, and because the
/// migrator computes its unapplied set up front, the loser died with
/// `SQLITE_BUSY` or "table already exists" — fatal at the `AppDatabase()` call
/// site and recurring every launch (the migration never committed). A busy
/// timeout alone does not fix it; the connections must be serialized around the
/// whole `migrate()` call.
struct AppDatabaseConcurrentMigrationTests {
    @Test
    func twoConnectionsMigrateSameFileConcurrently() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppDatabaseConcurrentMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let dbURL = dir.appendingPathComponent("AppDatabase.sqlite")

        @Sendable
        func openAndMigrate() throws {
            // The full production open+migrate path (pool open + WAL + migrate)
            // under the cross-process lock, exactly as each of the app / widget /
            // extension processes runs it.
            _ = try AppDatabase(onDiskAt: dbURL)
        }

        // Start both migrations concurrently against the same fresh file. The
        // cross-process lock serializes them; the second connection then sees the
        // migrations already applied and no-ops. Either task throwing fails here.
        let first = Task.detached { try openAndMigrate() }
        let second = Task.detached { try openAndMigrate() }
        try await first.value
        try await second.value
    }
}
