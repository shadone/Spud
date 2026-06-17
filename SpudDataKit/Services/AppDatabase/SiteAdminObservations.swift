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

public extension AppDatabase {
    /// One-shot read of a site's admins (ordered) for the given instance.
    func siteAdminsSync(forInstanceActorId actorId: InstanceActorId) -> [SiteAdminRecord] {
        do {
            return try writer.read { db in
                try Self.fetchSiteAdmins(in: db, instanceActorId: actorId.actorId)
            }
        } catch {
            logger.error("siteAdminsSync failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Live observation of a site's admins for the given instance.
    func observeSiteAdmins(forInstanceActorId actorId: InstanceActorId) -> AsyncStream<[SiteAdminRecord]> {
        let normalized = actorId.actorId
        let observation = ValueObservation
            .tracking { db in
                try Self.fetchSiteAdmins(in: db, instanceActorId: normalized)
            }
            .removeDuplicates()
        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("observeSiteAdmins failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    private static func fetchSiteAdmins(in db: Database, instanceActorId: String) throws -> [SiteAdminRecord] {
        try SiteAdminRecord.fetchAll(db, sql: """
                SELECT siteAdmin.*
                FROM siteAdmin
                JOIN site ON site.id = siteAdmin.siteId
                JOIN instance ON instance.id = site.instanceId
                WHERE instance.actorId = ?
                ORDER BY siteAdmin.ordinal ASC
            """, arguments: [instanceActorId])
    }
}
