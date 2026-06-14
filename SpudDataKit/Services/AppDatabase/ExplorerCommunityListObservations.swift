//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

/// Produces ``CommunityListRow`` values from the Lemmy Explorer community
/// directory (``ExplorerCommunityRecord``) for the Discover surfaces. The whole
/// directory is loaded into memory once; ranking, filtering, same-name
/// de-duplication and the Trending/Rising rails are then computed by the pure
/// ``ExplorerCommunityDirectory`` over that working set. The directory only
/// changes on a seed import or background refresh, so the cost is paid rarely.
public extension AppDatabase {
    /// One-shot snapshot of the whole community directory (ordered by Explorer
    /// score, highest first) for seeding a Discover screen before its
    /// observation starts.
    func explorerCommunityListRowsSync() -> [CommunityListRow] {
        do {
            return try writer.read { db in try Self.fetchExplorerCommunityListRows(in: db) }
        } catch {
            logger.error("explorerCommunityListRowsSync failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Live observation of the community directory. Emits the initial snapshot
    /// immediately, then again whenever the directory changes (seed import or
    /// background refresh).
    func observeExplorerCommunityListRows() -> AsyncStream<[CommunityListRow]> {
        let observation = ValueObservation
            .tracking { db in try Self.fetchExplorerCommunityListRows(in: db) }
            .removeDuplicates()
        return AsyncStream { continuation in
            let cancellable = observation.start(
                in: writer,
                scheduling: .async(onQueue: .global(qos: .userInitiated))
            ) { error in
                logger.error("observeExplorerCommunityListRows failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    private static func fetchExplorerCommunityListRows(in db: Database) throws -> [CommunityListRow] {
        try ExplorerCommunityRecord
            .order(ExplorerCommunityRecord.Columns.score.desc)
            .fetchAll(db)
            .map(CommunityListRow.init(explorerCommunity:))
    }
}

public extension CommunityListRow {
    /// Builds a Discover row from an Explorer directory record.
    init(explorerCommunity record: ExplorerCommunityRecord) {
        self.init(
            id: record.id ?? 0,
            communityUrl: record.url,
            instanceHost: record.baseurl,
            name: record.name,
            title: record.title,
            descriptionText: record.descriptionText,
            iconUrl: record.iconUrl.flatMap(URL.init(string:)),
            isNsfw: record.isNsfw,
            isSuspicious: record.isSuspicious,
            numberOfSubscribers: record.numberOfSubscribers,
            numberOfPosts: record.numberOfPosts,
            numberOfComments: record.numberOfComments,
            usersActiveWeek: record.usersActiveWeek,
            usersActiveMonth: record.usersActiveMonth,
            score: record.score,
            publishedAt: record.publishedAt
        )
    }
}
