//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import OSLog

private let logger = Logger.appDatabase

extension AppDatabase {
    /// Upserts a single community owned by `accountId`. Returns the resolved
    /// community row id.
    @discardableResult
    public func upsertCommunity(
        from model: Components.Schemas.Community,
        accountId: Int64
    ) async throws -> Int64 {
        try await writer.write { db in
            try Self.upsertCommunity(from: model, accountId: accountId, in: db)
        }
    }

    /// Replaces the followed-community set for `accountId` with the provided
    /// list. Communities are upserted first; the junction table is then
    /// rewritten in a single transaction so observers see one consistent
    /// snapshot.
    public func setFollowedCommunities(
        accountId: Int64,
        follows: [Components.Schemas.CommunityFollowerView]
    ) async throws {
        try await writer.write { db in
            var communityRowIds: [Int64] = []
            for follow in follows {
                let id = try Self.upsertCommunity(
                    from: follow.community,
                    accountId: accountId,
                    in: db
                )
                communityRowIds.append(id)
            }

            try AccountFollowedCommunityRecord
                .filter(Column("accountId") == accountId)
                .deleteAll(db)

            for communityRowId in communityRowIds {
                let junction = AccountFollowedCommunityRecord(
                    accountId: accountId,
                    communityId: communityRowId
                )
                try junction.insert(db)
            }
        }
    }

    static func upsertCommunity(
        from model: Components.Schemas.Community,
        accountId: Int64,
        in db: Database
    ) throws -> Int64 {
        let now = Date()

        if var existing = try CommunityRecord
            .filter(Column("accountId") == accountId)
            .filter(Column("communityId") == Int64(model.id))
            .fetchOne(db)
        {
            Self.apply(model: model, to: &existing, now: now)
            try existing.update(db)
            return existing.id!
        }

        var record = CommunityRecord(
            accountId: accountId,
            communityId: Int64(model.id),
            createdAt: now,
            updatedAt: now
        )
        Self.apply(model: model, to: &record, now: now)
        try record.insert(db)
        return record.id!
    }

    static func apply(
        model: Components.Schemas.Community,
        to record: inout CommunityRecord,
        now: Date
    ) {
        record.name = model.name
        record.title = model.title
        record.descriptionText = model.description
        record.actorId = model.actor_id
        record.iconUrl = model.icon
        record.bannerUrl = model.banner
        record.isHidden = model.hidden
        record.isLocal = model.local
        record.isNsfw = model.nsfw
        record.isPostingRestrictedToMods = model.posting_restricted_to_mods
        record.isRemoved = model.removed
        record.communityCreatedDate = model.published
        record.communityUpdatedDate = model.updated
        record.updatedAt = now
    }
}
