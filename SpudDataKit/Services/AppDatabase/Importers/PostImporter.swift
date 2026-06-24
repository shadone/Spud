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
        from view: Components.Schemas.PostView,
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
        from views: [Components.Schemas.PostView],
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
        from view: Components.Schemas.PostView,
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
            if pendingKinds.contains(.save) { existing.isSaved = preserved.isSaved }
            if pendingKinds.contains(.hide) { existing.isHidden = preserved.isHidden }
            try existing.update(db)
            return existing.id!
        }

        var record = PostRecord(
            accountId: accountId,
            communityId: communityRowId,
            creatorId: creatorId,
            postId: serverPostId,
            title: view.post.name,
            originalPostUrl: view.post.ap_id,
            published: view.post.published,
            createdAt: now,
            updatedAt: now
        )
        apply(view: view, to: &record, now: now)
        try record.insert(db)
        return record.id!
    }

    private static func apply(
        view: Components.Schemas.PostView,
        to record: inout PostRecord,
        now: Date
    ) {
        let post = view.post
        record.title = post.name
        record.body = post.body
        record.url = post.url
        record.urlEmbedTitle = post.embed_title
        record.urlEmbedDescription = post.embed_description
        record.thumbnailUrl = post.thumbnail_url
        // `image_details` (width/height) rides on the PostView, not the Post, and
        // is only present when the instance's media service processed the image.
        record.imageWidth = view.image_details.map { Int($0.width) }
        record.imageHeight = view.image_details.map { Int($0.height) }
        record.altText = post.alt_text
        record.originalPostUrl = post.ap_id
        record.published = post.published

        let counts = view.counts
        record.score = Int64(counts.score)
        record.numberOfUpvotes = Int64(counts.upvotes)
        record.numberOfDownvotes = Int64(counts.downvotes)
        record.numberOfComments = Int64(counts.comments)

        record.isRead = view.read
        record.isSaved = view.saved
        record.isHidden = view.hidden

        record.isRemoved = post.removed
        record.isLocked = post.locked
        record.isFeaturedCommunity = post.featured_community
        record.isFeaturedLocal = post.featured_local
        record.isDeleted = post.deleted

        switch view.my_vote {
        case 1: record.voteStatus = 1
        case -1: record.voteStatus = 0
        case 0, nil: record.voteStatus = nil
        default:
            logger.assertionFailure("Unexpected my_vote \(String(describing: view.my_vote)) for post \(post.id)")
            record.voteStatus = nil
        }

        record.updatedAt = now
    }
}
