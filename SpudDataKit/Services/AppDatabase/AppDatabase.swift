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

    /// In-memory database for tests and ephemeral use.
    public static func inMemory() throws -> AppDatabase {
        let queue = try DatabaseQueue(configuration: makeConfiguration())
        return try AppDatabase(writer: queue)
    }

    /// Default initializer opens the shared on-disk database in the App Group.
    public convenience init() throws {
        let url = try Self.defaultStoreURL()
        let pool = try DatabasePool(path: url.path, configuration: Self.makeConfiguration())
        try self.init(writer: pool)
    }

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    // MARK: - Configuration

    private static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.label = "AppDatabase"
        #if DEBUG
        config.publicStatementArguments = true
        #endif
        return config
    }

    private static func defaultStoreURL() throws -> URL {
        let appGroupIdentifier = "group.info.ddenis.Spud.shared"
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            throw AppDatabaseError.appGroupContainerUnavailable
        }
        let directory = containerURL.appendingPathComponent("AppDatabase", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("AppDatabase.sqlite", isDirectory: false)
    }
}

@MainActor
public protocol HasAppDatabase {
    var appDatabase: AppDatabase { get }
}
