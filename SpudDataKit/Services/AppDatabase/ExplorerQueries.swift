//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// One-shot synchronous reads over the Lemmy Explorer directory cache.
/// Reactive observations are added per consuming feature (see ``ExplorerService``).
public extension AppDatabase {
    func explorerInstanceCountSync() -> Int {
        (try? writer.read { db in try ExplorerInstanceRecord.fetchCount(db) }) ?? 0
    }

    func explorerCommunityCountSync() -> Int {
        (try? writer.read { db in try ExplorerCommunityRecord.fetchCount(db) }) ?? 0
    }

    /// Top instances by Explorer score (highest first). Used by the instance picker.
    func topExplorerInstancesSync(limit: Int = 50) -> [ExplorerInstanceRecord] {
        (try? writer.read { db in
            try ExplorerInstanceRecord
                .order(ExplorerInstanceRecord.Columns.score.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    /// Top communities by Explorer score (highest first). Used by Discover.
    func topExplorerCommunitiesSync(limit: Int = 50) -> [ExplorerCommunityRecord] {
        (try? writer.read { db in
            try ExplorerCommunityRecord
                .order(ExplorerCommunityRecord.Columns.score.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    /// Full Explorer community record for `url` (e.g.
    /// "https://lemmy.world/c/technology"), for the community vitality strip.
    func explorerCommunitySync(url: String) -> ExplorerCommunityRecord? {
        try? writer.read { db in
            try ExplorerCommunityRecord
                .filter(ExplorerCommunityRecord.Columns.url == url)
                .fetchOne(db)
        }
    }

    func explorerDatasetMetaSync(_ dataset: ExplorerDataset) -> ExplorerDatasetMetaRecord? {
        try? writer.read { db in
            try ExplorerDatasetMetaRecord.fetchOne(db, key: dataset.rawValue)
        }
    }

    /// Most recent successful Explorer refresh across all datasets, for the
    /// "Community Data" settings screen. Nil when nothing has been fetched yet.
    func explorerLastFetchedAtSync() -> Date? {
        ExplorerDataset.allCases
            .compactMap { explorerDatasetMetaSync($0)?.lastFetchedAt }
            .max()
    }

    /// True when the instance directory is still the bundled seed and has never
    /// been refreshed from the network — the first-launch state. A seed import
    /// writes `partCount` 0; a network refresh writes the real (non-zero) part
    /// count. Used by the instance picker to refresh once on the first login.
    func explorerInstancesAreSeedOnlySync() -> Bool {
        (explorerDatasetMetaSync(.instances)?.partCount ?? 0) == 0
    }

    /// Full Explorer instance record for `baseurl` (e.g. "lemmy.world"), for the
    /// instance detail screen.
    func explorerInstanceSync(baseurl: String) -> ExplorerInstanceRecord? {
        try? writer.read { db in
            try ExplorerInstanceRecord
                .filter(ExplorerInstanceRecord.Columns.baseurl == baseurl)
                .fetchOne(db)
        }
    }

    /// Client-side instance search over the bundled Lemmy Explorer directory.
    /// Matches `baseurl` OR `name` case-insensitively containing `query`,
    /// ordered by total users (largest first), capped at `limit`. Backs the
    /// Search screen's `.instances` scope (Lemmy has no federated instance
    /// search type). An empty/whitespace query returns nothing.
    func searchExplorerInstancesSync(query: String, limit: Int = 50) -> [ExplorerInstanceRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Escape LIKE metacharacters so a literal "%"/"_" in the query matches
        // literally, then wrap with wildcards for a contains match.
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escaped)%"

        return (try? writer.read { db in
            try ExplorerInstanceRecord
                .filter(
                    ExplorerInstanceRecord.Columns.baseurl.like(pattern, escape: "\\")
                        || ExplorerInstanceRecord.Columns.name.like(pattern, escape: "\\")
                )
                .order(ExplorerInstanceRecord.Columns.usersTotal.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }
}
