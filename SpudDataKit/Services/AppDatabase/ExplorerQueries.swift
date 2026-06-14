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

    func explorerDatasetMetaSync(_ dataset: ExplorerDataset) -> ExplorerDatasetMetaRecord? {
        try? writer.read { db in
            try ExplorerDatasetMetaRecord.fetchOne(db, key: dataset.rawValue)
        }
    }
}
