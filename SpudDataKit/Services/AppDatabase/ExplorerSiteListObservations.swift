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

/// Produces ``SiteListRow`` values from the Lemmy Explorer instance directory
/// (``ExplorerInstanceRecord``), ranked by Explorer score. Reuses `SiteListRow`
/// so the instance picker and login flow are unchanged — they just see the full
/// ranked directory instead of a hardcoded list.
public extension AppDatabase {
    /// One-shot ranked snapshot (highest Explorer score first) for seeding the
    /// instance picker before its observation starts.
    func explorerSiteListRowsSync() -> [SiteListRow] {
        do {
            return try writer.read { db in try Self.fetchExplorerSiteListRows(in: db) }
        } catch {
            logger.error("explorerSiteListRowsSync failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Live ranked observation of the Explorer instance directory. Emits the
    /// initial snapshot immediately, then again whenever the directory changes
    /// (e.g. the background seed import or refresh completes).
    func observeExplorerSiteListRows() -> AsyncStream<[SiteListRow]> {
        let observation = ValueObservation
            .tracking { db in try Self.fetchExplorerSiteListRows(in: db) }
            .removeDuplicates()
        return AsyncStream { continuation in
            let cancellable = observation.start(
                in: writer,
                scheduling: .async(onQueue: .global(qos: .userInitiated))
            ) { error in
                logger.error("observeExplorerSiteListRows failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    private static func fetchExplorerSiteListRows(in db: Database) throws -> [SiteListRow] {
        let records = try ExplorerInstanceRecord
            .order(ExplorerInstanceRecord.Columns.score.desc)
            .fetchAll(db)
        return records.compactMap { record -> SiteListRow? in
            let actorIdString = record.url ?? "https://\(record.baseurl)"
            guard let instance = InstanceActorId(from: actorIdString) else {
                logger.error("Skipping unparseable explorer instance: \(record.baseurl, privacy: .public)")
                return nil
            }
            return SiteListRow(
                id: record.id ?? 0,
                instance: instance,
                hostname: record.baseurl,
                name: record.name,
                descriptionText: record.descriptionText,
                iconUrl: record.iconUrl.flatMap(URL.init(string:)),
                score: record.score,
                usersTotal: record.usersTotal,
                usersActiveMonth: record.usersActiveMonth,
                uptimeAllTime: record.uptimeAllTime,
                isNsfw: record.isNsfw,
                isOpenRegistration: record.isOpenRegistration,
                languageCodes: record.languageCodes,
                tags: record.tagList
            )
        }
    }
}
