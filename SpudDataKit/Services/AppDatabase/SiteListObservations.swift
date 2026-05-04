//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog
import SpudUtilKit

private let logger = Logger.appDatabase

/// Snapshot row for the Site picker (`SiteListViewController` / Login icon).
/// Joins SiteRecord with its InstanceRecord so the UI can render in one read.
public struct SiteListRow: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let instance: InstanceActorId
    public let hostname: String
    public let name: String?
    public let descriptionText: String?
    public let iconUrl: URL?

    public init(
        id: Int64,
        instance: InstanceActorId,
        hostname: String,
        name: String?,
        descriptionText: String?,
        iconUrl: URL?
    ) {
        self.id = id
        self.instance = instance
        self.hostname = hostname
        self.name = name
        self.descriptionText = descriptionText
        self.iconUrl = iconUrl
    }
}

public extension AppDatabase {
    /// Synchronous one-shot read of every site, ordered by GRDB row id.
    /// Used by SiteListViewController to seed its initial table view state
    /// before subscribing to observeAllSites().
    func allSiteListRowsSync() -> [SiteListRow] {
        do {
            return try writer.read { db in
                try Self.fetchSiteListRows(in: db)
            }
        } catch {
            logger.error("allSiteListRowsSync failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Live observation of every site. Emits the initial snapshot
    /// immediately, then a fresh array on every relevant transaction.
    func observeAllSites() -> AsyncStream<[SiteListRow]> {
        let observation = ValueObservation
            .tracking { db in
                try Self.fetchSiteListRows(in: db)
            }
            .removeDuplicates()
        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer) { error in
                logger.error("observeAllSites failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    private static func fetchSiteListRows(in db: Database) throws -> [SiteListRow] {
        let rows = try Row.fetchAll(db, sql: """
                SELECT
                    site.id              AS siteId,
                    site.name            AS name,
                    site.descriptionText AS descriptionText,
                    site.iconUrl         AS iconUrl,
                    instance.actorId     AS actorId
                FROM site
                JOIN instance ON instance.id = site.instanceId
                ORDER BY site.id ASC
            """)
        return rows.compactMap { row in
            let actorIdRaw: String = row["actorId"]
            guard let instance = InstanceActorId(from: actorIdRaw) else {
                logger.error("Skipping unparseable instance actorId: \(actorIdRaw, privacy: .public)")
                return nil
            }
            let iconRaw: String? = row["iconUrl"]
            let iconUrl = iconRaw.flatMap(URL.init(string:))
            return SiteListRow(
                id: row["siteId"],
                instance: instance,
                hostname: instance.host,
                name: row["name"],
                descriptionText: row["descriptionText"],
                iconUrl: iconUrl
            )
        }
    }
}
