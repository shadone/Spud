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
        from model: Lemmy.Community,
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
    ///
    /// When `respectsPendingOutbox` is `true` (the default), communities with an
    /// in-flight optimistic `.subscribe` op are exempted from the rewrite: they
    /// keep their CURRENT junction membership so an un-synced subscribe/unsubscribe
    /// survives this server reconcile in BOTH directions — an optimistic subscribe
    /// absent from `follows` keeps its junction row, and an optimistic unsubscribe
    /// still present in `follows` is not resurrected. The outbox performer confirms
    /// the authoritative state separately via `upsertCommunity`.
    public func setFollowedCommunities(
        accountId: Int64,
        follows: [Lemmy.Community],
        respectsPendingOutbox: Bool = true
    ) async throws {
        try await writer.write { db in
            var communityRowIds: [Int64] = []
            for follow in follows {
                let id = try Self.upsertCommunity(
                    from: follow,
                    accountId: accountId,
                    in: db
                )
                communityRowIds.append(id)
            }

            // Communities with an in-flight optimistic subscribe/unsubscribe are
            // governed by the outbox, not this server snapshot. Their CURRENT
            // junction membership is preserved across the wholesale rewrite. This
            // stays a bulk delete + bulk insert (no per-row server diffing); in the
            // common case (no pending subscribes) the lookup returns empty and the
            // behaviour is identical to before.
            let pendingRowIds = respectsPendingOutbox
                ? try Self.pendingSubscribeCommunityRowIds(db, accountId: accountId)
                : []
            let preservedRowIds = pendingRowIds.isEmpty
                ? []
                : try Self.followedCommunityRowIds(db, accountId: accountId, among: pendingRowIds)

            try AccountFollowedCommunityRecord
                .filter(Column("accountId") == accountId)
                .deleteAll(db)

            // Re-insert the server follows (minus the pending ones), then restore
            // the preserved optimistic membership. A set tracks what's inserted so
            // the same community isn't inserted twice.
            var inserted: Set<Int64> = []
            for communityRowId in communityRowIds where !pendingRowIds.contains(communityRowId) {
                guard inserted.insert(communityRowId).inserted else { continue }
                let junction = AccountFollowedCommunityRecord(
                    accountId: accountId,
                    communityId: communityRowId
                )
                try junction.insert(db)
            }
            for communityRowId in preservedRowIds where !inserted.contains(communityRowId) {
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
    ///
    /// When `respectsPendingOutbox` is `true` (the default), a community with an
    /// in-flight optimistic `.subscribe` op keeps its optimistic `subscribedState`
    /// and junction membership — the server's (stale) `subscribed` value and the
    /// junction sync are skipped, while every other column still imports. The
    /// outbox performer's authoritative post-send mirror passes `false` to write
    /// the confirmed server state through.
    @discardableResult
    public func upsertCommunity(
        from view: Lemmy.CommunityView,
        accountId: Int64,
        respectsPendingOutbox: Bool = true
    ) async throws -> Int64 {
        try await writer.write { db in
            try Self.upsertCommunity(
                from: view,
                accountId: accountId,
                respectsPendingOutbox: respectsPendingOutbox,
                in: db
            )
        }
    }

    static func upsertCommunity(
        from model: Lemmy.Community,
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
        from view: Lemmy.CommunityView,
        accountId: Int64,
        respectsPendingOutbox: Bool = true,
        in db: Database
    ) throws -> Int64 {
        let now = Date()
        let serverCommunityId = Int64(view.community.id)

        // When a subscribe/unsubscribe is in flight the local `subscribedState`
        // and junction reflect the optimistic projection, not the server; skip
        // overwriting them so the reconcile can't clobber the un-synced tap.
        let hasPendingSubscribe = try respectsPendingOutbox
            && (AppDatabase.pendingOutboxKinds(
                db,
                accountId: accountId,
                entityType: "community",
                entityServerId: serverCommunityId
            )).contains(.subscribe)

        let communityRowId: Int64
        if var existing = try CommunityRecord
            .filter(Column("accountId") == accountId)
            .filter(Column("communityId") == serverCommunityId)
            .fetchOne(db)
        {
            let preservedSubscribedState = existing.subscribedState
            Self.apply(model: view.community, to: &existing, now: now)
            Self.apply(view: view, to: &existing)
            if hasPendingSubscribe {
                existing.subscribedState = preservedSubscribedState
            }
            try existing.update(db)
            communityRowId = existing.id!
        } else {
            var record = CommunityRecord(
                accountId: accountId,
                communityId: serverCommunityId,
                createdAt: now,
                updatedAt: now
            )
            Self.apply(model: view.community, to: &record, now: now)
            Self.apply(view: view, to: &record)
            try record.insert(db)
            communityRowId = record.id!
        }

        // Preserve the optimistic junction membership while a subscribe is
        // pending; otherwise sync it to the server's subscribed state.
        if !hasPendingSubscribe {
            try Self.syncFollowedCommunityJunction(
                accountId: accountId,
                communityRowId: communityRowId,
                followState: view.followState,
                in: db
            )
        }

        return communityRowId
    }

    /// Inserts or removes the `accountFollowedCommunity` junction row so the
    /// followed-communities observation reflects `followState`. Pending (and the
    /// v4-only approval-required) counts as followed (the user has requested
    /// subscription); denied and not-following do not.
    static func syncFollowedCommunityJunction(
        accountId: Int64,
        communityRowId: Int64,
        followState: FollowState,
        in db: Database
    ) throws {
        let isFollowed = CommunitySubscribedState(followState: followState).isSubscribed
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
        model: Lemmy.Community,
        to record: inout CommunityRecord,
        now: Date
    ) {
        record.name = model.name
        record.title = model.title
        // v4 renamed the community's short `description` to `sidebar`; the neutral
        // Community carries only `sidebar`, which the local `descriptionText`
        // column mirrors.
        record.descriptionText = model.sidebar
        record.actorId = model.apId
        record.iconUrl = model.iconUrl
        record.bannerUrl = model.bannerUrl
        // v4 replaced v3's `hidden: Bool` with a richer `visibility`; anything
        // other than public reads as hidden for the local filter flag.
        record.isHidden = model.visibility != ._public
        record.isLocal = model.local
        record.isNsfw = model.nsfw
        record.isPostingRestrictedToMods = model.postingRestrictedToMods
        record.isRemoved = model.removed
        record.communityCreatedDate = model.publishedAt
        record.communityUpdatedDate = model.updatedAt
        record.updatedAt = now
    }

    /// Applies the view-level fields (subscribed state + counts). The neutral
    /// surface flattens the counts onto the `Community` itself (v3 kept them on a
    /// separate `counts` aggregate), and the account's follow relationship is the
    /// derived `followState`.
    static func apply(
        view: Lemmy.CommunityView,
        to record: inout CommunityRecord
    ) {
        record.subscribedState = CommunitySubscribedState(followState: view.followState).rawValue
        record.numberOfSubscribers = view.community.subscribers
        record.numberOfPosts = view.community.posts
        record.numberOfComments = view.community.comments
    }
}
