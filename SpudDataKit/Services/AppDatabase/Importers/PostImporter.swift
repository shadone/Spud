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

public extension AppDatabase {
    /// Sets `isRead` on the matching post row. Silently no-ops if the post
    /// row hasn't been imported yet.
    func setPostIsRead(
        accountId: Int64,
        serverPostId: Int64,
        isRead: Bool
    ) async throws {
        try await writer.write { db in
            guard
                var record = try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == serverPostId)
                .fetchOne(db)
            else { return }
            record.isRead = isRead
            record.updatedAt = Date()
            try record.update(db)
        }
    }

    /// Sets `isHidden` on the matching post row. Silently no-ops if the post
    /// row hasn't been imported yet.
    func setPostIsHidden(
        accountId: Int64,
        serverPostId: Int64,
        isHidden: Bool
    ) async throws {
        try await writer.write { db in
            guard
                var record = try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == serverPostId)
                .fetchOne(db)
            else { return }
            record.isHidden = isHidden
            record.updatedAt = Date()
            try record.update(db)
        }
    }

    /// Upserts a post tied to `accountId` along with its creator and
    /// community, so all foreign keys are satisfied. Returns the resolved
    /// post row id.
    ///
    /// When `respectsPendingOutbox` is `true` (the default), any pending
    /// outbox operations for this post will prevent the corresponding
    /// optimistic fields from being overwritten by server data.
    @discardableResult
    func upsertPost(
        from view: Lemmy.PostView,
        accountId: Int64,
        siteId: Int64,
        respectsPendingOutbox: Bool = true
    ) async throws -> Int64 {
        try await writer.write { db in
            try Self.upsertPost(from: view, accountId: accountId, siteId: siteId, respectsPendingOutbox: respectsPendingOutbox, in: db)
        }
    }

    /// Upserts several posts in a single write transaction, rather than one
    /// transaction per post. Atomic: if any upsert throws the whole batch rolls
    /// back. No-ops on an empty input.
    func upsertPosts(
        from views: [Lemmy.PostView],
        accountId: Int64,
        siteId: Int64,
        respectsPendingOutbox: Bool = true
    ) async throws {
        guard !views.isEmpty else { return }
        try await writer.write { db in
            for view in views {
                _ = try Self.upsertPost(
                    from: view,
                    accountId: accountId,
                    siteId: siteId,
                    respectsPendingOutbox: respectsPendingOutbox,
                    in: db
                )
            }
        }
    }

    internal static func upsertPost(
        from view: Lemmy.PostView,
        accountId: Int64,
        siteId: Int64,
        respectsPendingOutbox: Bool = true,
        in db: Database
    ) throws -> Int64 {
        let creatorId = try AppDatabase.upsertPerson(
            from: view.creator,
            siteId: siteId,
            in: db
        )
        // The neutral bare `Person` carries no site-ban (v4 moved `banned` onto the
        // views), but v4's `PostView` exposes the creator's instance-wide ban as
        // `creatorBanned`. Mirror it onto the creator's person row so the feed /
        // post-detail author-status indicator lights up from a feed import — matching
        // v3, where the bare `Person.banned` set this — instead of only after a
        // separate `PersonView` (profile) import. `PostListRow`/`PostDetailHeaderRow`
        // read `isCreatorSiteBanned` from the joined `person.isBanned`.
        if var creatorRecord = try PersonRecord.fetchOne(db, key: creatorId) {
            creatorRecord.isBanned = view.creatorBanned
            try creatorRecord.update(db)
        }
        let communityRowId = try AppDatabase.upsertCommunity(
            from: view.community,
            accountId: accountId,
            in: db
        )

        let now = Date()
        let serverPostId = Int64(view.post.id)

        if var existing = try PostRecord
            .filter(Column("accountId") == accountId)
            .filter(Column("postId") == serverPostId)
            .fetchOne(db)
        {
            let pendingKinds = respectsPendingOutbox
                ? try AppDatabase.pendingOutboxKinds(db, accountId: accountId, entityType: "post", entityServerId: serverPostId)
                : []
            let preserved = existing
            existing.creatorId = creatorId
            existing.communityId = communityRowId
            apply(view: view, to: &existing, now: now)
            if pendingKinds.contains(.vote) {
                existing.voteStatus = preserved.voteStatus
                existing.score = preserved.score
                existing.numberOfUpvotes = preserved.numberOfUpvotes
                existing.numberOfDownvotes = preserved.numberOfDownvotes
            }
            if pendingKinds.contains(.save) {
                existing.isSaved = preserved.isSaved
            }
            if pendingKinds.contains(.hide) {
                existing.isHidden = preserved.isHidden
            }
            if pendingKinds.contains(.delete) {
                existing.isDeleted = preserved.isDeleted
            }
            // A content edit lives in the composer outbox (`outboundContent`), not
            // the mutation outbox (`pendingOperation`), so it isn't covered by
            // `pendingKinds`. While the edit is un-synced (sending or failed),
            // preserve the locally-applied title/body/url/nsfw so a feed/`getPost`
            // refresh can't revert the user's edit. The successful `editPost`
            // upsert bypasses this (it passes `respectsPendingOutbox: false`).
            if respectsPendingOutbox,
               try AppDatabase.hasPendingOutboundPostEdit(db, accountId: accountId, serverPostId: serverPostId)
            {
                existing.title = preserved.title
                existing.body = preserved.body
                existing.url = preserved.url
                existing.isNsfw = preserved.isNsfw
            }
            try existing.update(db)
            return existing.id!
        }

        var record = PostRecord(
            accountId: accountId,
            communityId: communityRowId,
            creatorId: creatorId,
            postId: serverPostId,
            title: view.post.name,
            originalPostUrl: view.post.apId,
            published: view.post.publishedAt,
            createdAt: now,
            updatedAt: now
        )
        apply(view: view, to: &record, now: now)
        try record.insert(db)
        return record.id!
    }

    private static func apply(
        view: Lemmy.PostView,
        to record: inout PostRecord,
        now: Date
    ) {
        let post = view.post
        record.title = post.name
        record.body = post.body
        record.url = post.url
        record.urlEmbedTitle = post.embedTitle
        record.urlEmbedDescription = post.embedDescription
        record.thumbnailUrl = post.thumbnailUrl
        // Pixel dimensions of the post's image, so the post-detail header can
        // reserve the exact aspect ratio before the image loads (no row reflow
        // when it appears). Coalesce rather than assign: a later PostView that
        // omits dimensions (a backend not carrying `image_details`) must not
        // blank a previously-known size back to nil.
        record.imageWidth = post.imageWidth ?? record.imageWidth
        record.imageHeight = post.imageHeight ?? record.imageHeight
        record.altText = post.altText
        record.originalPostUrl = post.apId
        record.published = post.publishedAt

        record.score = post.score
        record.numberOfUpvotes = post.upvotes
        record.numberOfDownvotes = post.downvotes
        record.numberOfComments = post.comments

        record.isRead = view.isRead
        record.isSaved = view.isSaved
        record.isHidden = view.isHidden

        record.isRemoved = post.removed
        record.isLocked = post.locked
        record.isFeaturedCommunity = post.featuredCommunity
        record.isFeaturedLocal = post.featuredLocal
        record.isDeleted = post.deleted

        // Per-post creator context, mirroring the CommentView import. A later
        // feed/getPost re-import re-runs `apply`, so these stay current (unlike
        // the local-only `downloadedAt`, which `apply` deliberately never touches).
        record.isCreatorModerator = view.creatorIsModerator
        record.isCreatorAdmin = view.creatorIsAdmin
        record.isCreatorBannedFromCommunity = view.creatorBannedFromCommunity

        // A fresh authoritative PostView means the post exists again — clear any
        // stale "unavailable" tombstone from a prior couldnt_find_post.
        record.isUnavailable = false
        record.isNsfw = post.nsfw

        // Map the neutral `VoteDirection` onto the record's stored encoding
        // (1 = upvote, 0 = downvote, nil = no vote).
        switch view.myVote {
        case .up: record.voteStatus = 1
        case .down: record.voteStatus = 0
        case .none: record.voteStatus = nil
        }

        record.updatedAt = now
    }
}
