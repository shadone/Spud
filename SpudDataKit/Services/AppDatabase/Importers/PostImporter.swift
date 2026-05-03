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
    /// Sets `isRead` on the matching post row. Silently no-ops if the post
    /// row hasn't been imported yet.
    public func setPostIsRead(
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

    /// Upserts a post tied to `accountId` along with its creator and
    /// community, so all foreign keys are satisfied. Returns the resolved
    /// post row id.
    @discardableResult
    public func upsertPost(
        from view: Components.Schemas.PostView,
        accountId: Int64,
        siteId: Int64
    ) async throws -> Int64 {
        try await writer.write { db in
            try Self.upsertPost(from: view, accountId: accountId, siteId: siteId, in: db)
        }
    }

    static func upsertPost(
        from view: Components.Schemas.PostView,
        accountId: Int64,
        siteId: Int64,
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
            existing.creatorId = creatorId
            existing.communityId = communityRowId
            apply(view: view, to: &existing, now: now)
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
        record.originalPostUrl = post.ap_id
        record.published = post.published

        let counts = view.counts
        record.score = Int64(counts.score)
        record.numberOfUpvotes = Int64(counts.upvotes)
        record.numberOfDownvotes = Int64(counts.downvotes)
        record.numberOfComments = Int64(counts.comments)

        record.isRead = view.read

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
