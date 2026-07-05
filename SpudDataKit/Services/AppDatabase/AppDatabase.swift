//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

/// GRDB-backed persistence facade. Replaces ``DataStore`` and Core Data.
///
/// Holds a single ``DatabasePool`` pointed at the App Group container so the
/// app, widget, and "Open in Spud" extension see the same database.
public final class AppDatabase: Sendable {
    public static let shared: AppDatabase = {
        do {
            return try AppDatabase()
        } catch {
            fatalError("Failed to open AppDatabase: \(error)")
        }
    }()

    public let writer: any DatabaseWriter

    /// URL of the on-disk SQLite file for diagnostics and the Preferences
    /// "show database in Files" affordance. Nil when the database is
    /// in-memory.
    public let storeURL: URL?

    /// On-disk size in bytes, or zero if not on disk or unreachable.
    public var sizeInBytes: UInt64 {
        guard
            let storeURL,
            let attrs = try? FileManager.default.attributesOfItem(atPath: storeURL.path)
        else {
            return 0
        }
        return (attrs[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// In-memory database for tests and ephemeral use.
    public static func inMemory() throws -> AppDatabase {
        let queue = try DatabaseQueue(configuration: makeConfiguration())
        return try AppDatabase(writer: queue, storeURL: nil)
    }

    /// Opens (and migrates) the shared on-disk database in the App Group container.
    public convenience init() throws {
        let url = try Self.defaultStoreURL()
        try self.init(onDiskAt: url)
    }

    /// Opens and migrates the on-disk database at `url`, holding a cross-process
    /// advisory lock across BOTH the pool open and the migration. Exposed
    /// (internal) so tests can drive the shared-file path at a temp URL.
    ///
    /// The file is shared across the app + widget + share extensions (App Group
    /// container), so several processes may open it at once. Two things race, and
    /// neither is covered by the connection's busy timeout:
    ///  - the FIRST open of a fresh file runs `PRAGMA journal_mode = WAL`, which
    ///    needs a brief exclusive lock;
    ///  - `DatabaseMigrator` computes its unapplied set up front, so two
    ///    connections that both migrate a just-upgraded database each try to apply
    ///    the same migrations and the loser dies with `SQLITE_BUSY` /
    ///    "table already exists".
    /// Both were fatal at the `AppDatabase()` call site and recurred on every
    /// launch (the migration never committed — this is the build-24 crash).
    /// Serializing the whole open+migrate means a second process proceeds only
    /// after the first has finished and released the lock, by which point WAL is
    /// set and its fresh migration read finds nothing to do.
    convenience init(onDiskAt url: URL) throws {
        let pool = try Self.withCrossProcessLock(databaseURL: url) {
            let pool = try DatabasePool(path: url.path, configuration: Self.makeConfiguration())
            try Self.migrator.migrate(pool)
            return pool
        }
        try self.init(writer: pool, storeURL: url, migrating: false)
    }

    /// Designated initializer. Migrates unless `migrating` is false — the on-disk
    /// path passes false because ``init(onDiskAt:)`` already migrated under the
    /// cross-process lock. In-memory and injected-writer callers migrate here.
    public init(writer: any DatabaseWriter, storeURL: URL? = nil, migrating: Bool = true) throws {
        self.writer = writer
        self.storeURL = storeURL
        if migrating {
            try Self.migrator.migrate(writer)
        }
    }

    /// Runs `body` while holding an exclusive advisory lock on a sidecar file next
    /// to the database, so at most one process opens+migrates the shared file at a
    /// time. Falls back to running unlocked if the lock file can't be opened.
    private static func withCrossProcessLock<T>(
        databaseURL: URL,
        _ body: () throws -> T
    ) throws -> T {
        let lockURL = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("AppDatabase.migration.lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            logger.error("Migration lock open failed (errno \(errno)); proceeding without it")
            return try body()
        }
        defer { close(fd) }
        flock(fd, LOCK_EX) // blocks until this process holds the exclusive lock
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    // MARK: - Configuration

    /// The shared connection configuration. Exposed (internal) so tests can open
    /// additional connections that behave exactly like production — in particular
    /// with the busy timeout below, without which concurrent pool opens collide on
    /// `PRAGMA journal_mode = WAL`.
    static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.label = "AppDatabase"
        // The database lives in the App Group container and is opened by several
        // connections at once: within the app, TWO `DatabasePool`s exist at launch
        // — the DI-owned `appDatabase` and the `shared` singleton that the
        // launch-time prune tasks in `AppDelegate` touch — and the widget plus the
        // share extensions open the same file from their own processes. Without a
        // busy timeout, when two connections both have pending migrations to apply
        // they issue `BEGIN IMMEDIATE TRANSACTION` simultaneously and the loser
        // fails *immediately* with `SQLITE_BUSY` ("database is locked") rather than
        // waiting. That aborts the migration, kills the process at the
        // `try AppDatabase()` call site, and — because the migration never
        // commits — recurs on every relaunch: a permanent first-launch crash. It
        // stayed latent until v26/v27 made the first launch after an upgrade have
        // pending migrations. A busy timeout makes a contended writer wait for the
        // holder to commit; the migrator then sees the work already done and no-ops.
        config.busyMode = .timeout(10)
        #if DEBUG
        config.publicStatementArguments = true
        #endif
        return config
    }

    /// The `AppDatabase` directory inside the App Group container (holding the
    /// SQLite file plus its WAL/SHM sidecars and the migration lock). Does NOT
    /// create it — callers that need it on disk go through ``defaultStoreURL()``.
    static func defaultStoreDirectoryURL() throws -> URL {
        let appGroupIdentifier = "group.info.ddenis.Spud.shared"
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            throw AppDatabaseError.appGroupContainerUnavailable
        }
        return containerURL.appendingPathComponent("AppDatabase", isDirectory: true)
    }

    private static func defaultStoreURL() throws -> URL {
        let directory = try defaultStoreDirectoryURL()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("AppDatabase.sqlite", isDirectory: false)
    }
}

#if DEBUG
public extension AppDatabase {
    /// Test-only: deletes the on-disk `AppDatabase` directory in the App Group
    /// container so a UI test begins from a truly fresh install. Removes the
    /// whole directory (SQLite file + WAL/SHM sidecars + migration lock), not
    /// just the `.sqlite`, so nothing survives to be re-opened. No-op when the
    /// directory is absent or the App Group container is unavailable.
    ///
    /// Must run BEFORE ``AppDatabase/shared`` (or any pool) first opens the
    /// store — it is invoked at the top of `AppDelegate.init`, ahead of the DI
    /// graph. Gated behind the `SPUDWipeAppDatabase` launch argument; never
    /// reached in the shipping app.
    static func wipePersistentStoreForUITests() {
        guard let directory = try? defaultStoreDirectoryURL() else { return }
        wipePersistentStore(at: directory)
    }
}

extension AppDatabase {
    /// Deletes the database directory at `url`. Split out (and parameterized)
    /// from ``wipePersistentStoreForUITests()`` so unit tests can exercise it
    /// against a temp directory without touching the real shared container.
    /// Safe when the directory is absent (`removeItem` no-ops via `try?`).
    static func wipePersistentStore(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
#endif

@MainActor
public protocol HasAppDatabase {
    var appDatabase: AppDatabase { get }
}
