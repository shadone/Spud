//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// Translates decoded Lemmy Explorer DTOs into the directory tables.
///
/// Refresh is a wholesale replace: each row is written with the refresh's
/// `stamp` (INSERT OR REPLACE on the unique key), then rows still carrying an
/// older stamp are pruned. Pruning happens only after every part imported
/// successfully, so a failed refresh leaves the previous cache intact.
enum ExplorerImporter {
    static func upsertInstances(_ dtos: [ExplorerInstanceDTO], stamp: Date, db: Database) throws {
        for dto in dtos {
            var record = dto.makeRecord(updatedAt: stamp)
            try record.insert(db, onConflict: .replace)
        }
    }

    static func upsertCommunities(_ dtos: [ExplorerCommunityDTO], stamp: Date, db: Database) throws {
        for dto in dtos {
            var record = dto.makeRecord(updatedAt: stamp)
            try record.insert(db, onConflict: .replace)
        }
    }

    @discardableResult
    static func pruneInstances(olderThan stamp: Date, db: Database) throws -> Int {
        try ExplorerInstanceRecord
            .filter(ExplorerInstanceRecord.Columns.updatedAt < stamp)
            .deleteAll(db)
    }

    @discardableResult
    static func pruneCommunities(olderThan stamp: Date, db: Database) throws -> Int {
        try ExplorerCommunityRecord
            .filter(ExplorerCommunityRecord.Columns.updatedAt < stamp)
            .deleteAll(db)
    }

    static func updateMeta(
        datasetKey: String,
        stamp: Date,
        partCount: Int,
        recordCount: Int,
        db: Database
    ) throws {
        let existing = try ExplorerDatasetMetaRecord.fetchOne(db, key: datasetKey)
        var meta = existing ?? ExplorerDatasetMetaRecord(datasetKey: datasetKey)
        meta.lastFetchedAt = stamp
        meta.partCount = Int64(partCount)
        meta.recordCount = Int64(recordCount)
        if existing == nil {
            try meta.insert(db)
        } else {
            try meta.update(db)
        }
    }
}
