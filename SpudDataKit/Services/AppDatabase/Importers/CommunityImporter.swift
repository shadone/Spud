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

    /// Upserts a community from a full `CommunityView`, which additionally
    /// carries the account's subscribed state and aggregate counts. Keeps the
    /// `accountFollowedCommunity` junction table in sync with the subscribed
    /// state so the Subscriptions sidebar (which observes the junction) updates
    /// live. Returns the resolved community row id.
    @discardableResult
    public func upsertCommunity(
        from view: Components.Schemas.CommunityView,
        accountId: Int64
    ) async throws -> Int64 {
        try await writer.write { db in
            try Self.upsertCommunity(from: view, accountId: accountId, in: db)
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

    static func upsertCommunity(
        from view: Components.Schemas.CommunityView,
        accountId: Int64,
        in db: Database
    ) throws -> Int64 {
        let now = Date()

        let communityRowId: Int64
        if var existing = try CommunityRecord
            .filter(Column("accountId") == accountId)
            .filter(Column("communityId") == Int64(view.community.id))
            .fetchOne(db)
        {
            Self.apply(model: view.community, to: &existing, now: now)
            Self.apply(view: view, to: &existing)
            try existing.update(db)
            communityRowId = existing.id!
        } else {
            var record = CommunityRecord(
                accountId: accountId,
                communityId: Int64(view.community.id),
                createdAt: now,
                updatedAt: now
            )
            Self.apply(model: view.community, to: &record, now: now)
            Self.apply(view: view, to: &record)
            try record.insert(db)
            communityRowId = record.id!
        }

        try Self.syncFollowedCommunityJunction(
            accountId: accountId,
            communityRowId: communityRowId,
            subscribed: view.subscribed,
            in: db
        )

        return communityRowId
    }

    /// Inserts or removes the `accountFollowedCommunity` junction row so the
    /// followed-communities observation reflects `subscribed`. Pending counts
    /// as followed (the user has requested subscription).
    static func syncFollowedCommunityJunction(
        accountId: Int64,
        communityRowId: Int64,
        subscribed: Components.Schemas.SubscribedType,
        in db: Database
    ) throws {
        let isFollowed = subscribed != .NotSubscribed
        if isFollowed {
            let junction = AccountFollowedCommunityRecord(
                accountId: accountId,
                communityId: communityRowId
            )
            try junction.insert(db, onConflict: .ignore)
        } else {
            try AccountFollowedCommunityRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("communityId") == communityRowId)
                .deleteAll(db)
        }
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

    /// Applies the view-level fields (subscribed state + counts) that a bare
    /// `Community` model doesn't carry.
    static func apply(
        view: Components.Schemas.CommunityView,
        to record: inout CommunityRecord
    ) {
        record.subscribedState = view.subscribed.rawValue
        record.numberOfSubscribers = view.counts.subscribers
        record.numberOfPosts = view.counts.posts
        record.numberOfComments = view.counts.comments
    }
}
