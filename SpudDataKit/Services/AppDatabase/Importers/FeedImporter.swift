//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import OSLog
import SpudUtilKit

private let logger = Logger.appDatabase

extension AppDatabase {
    /// Resolves or creates the FeedRecord matching `feedKey`, capturing its
    /// type and sort. Returns the GRDB row id. Caller must already be inside
    /// a write transaction.
    static func upsertFeed(
        feedKey: String,
        accountId: Int64,
        feedType: FeedType,
        in db: Database
    ) throws -> Int64 {
        let now = Date()

        let frontpageListingType: String?
        let communityName: String?
        let communityInstanceActorId: String?
        let sortType: String

        switch feedType {
        case let .frontpage(listingType, sort):
            frontpageListingType = listingType.rawValue
            communityName = nil
            communityInstanceActorId = nil
            sortType = sort.rawValue
        case let .community(name, instance, sort):
            frontpageListingType = nil
            communityName = name
            communityInstanceActorId = instance.actorId
            sortType = sort.rawValue
        }

        if var existing = try FeedRecord
            .filter(Column("feedKey") == feedKey)
            .fetchOne(db)
        {
            existing.frontpageListingType = frontpageListingType
            existing.communityName = communityName
            existing.communityInstanceActorId = communityInstanceActorId
            existing.sortType = sortType
            try existing.update(db)
            return existing.id!
        }

        var record = FeedRecord(
            accountId: accountId,
            feedKey: feedKey,
            frontpageListingType: frontpageListingType,
            communityName: communityName,
            communityInstanceActorId: communityInstanceActorId,
            sortType: sortType,
            createdAt: now
        )
        try record.insert(db)
        return record.id!
    }

    /// Appends a new page worth of posts to the feed. Deduplicates against
    /// posts already linked to this feed via originalPostUrl (matching the
    /// legacy postActivityIds set on LemmyFeed). Returns the new pageId.
    @discardableResult
    public func appendFeedPage(
        feedKey: String,
        feedType: FeedType,
        accountId: Int64,
        siteId: Int64,
        posts: [Components.Schemas.PostView]
    ) async throws -> Int64 {
        try await writer.write { db in
            let feedId = try Self.upsertFeed(
                feedKey: feedKey,
                accountId: accountId,
                feedType: feedType,
                in: db
            )

            // Existing originalPostUrl values across all pages of this feed.
            let existingUrls: Set<String> = try Set(
                String.fetchAll(
                    db,
                    sql: """
                        SELECT post.originalPostUrl
                        FROM post
                        INNER JOIN pageElement ON pageElement.postId = post.id
                        INNER JOIN page ON page.id = pageElement.pageId
                        WHERE page.feedId = ?
                        """,
                    arguments: [feedId]
                )
            )

            let nextPagePosition: Int64 = try Int64(
                Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM page WHERE feedId = ?",
                    arguments: [feedId]
                ) ?? 0
            )

            var pageRecord = PageRecord(
                feedId: feedId,
                position: nextPagePosition
            )
            try pageRecord.insert(db)
            let pageId = pageRecord.id!

            var elementPosition: Int64 = 0
            for view in posts {
                let url = view.post.ap_id
                guard !existingUrls.contains(url) else { continue }

                let postRowId = try AppDatabase.upsertPost(
                    from: view,
                    accountId: accountId,
                    siteId: siteId,
                    in: db
                )

                var pageElement = PageElementRecord(
                    pageId: pageId,
                    postId: postRowId,
                    position: elementPosition
                )
                try pageElement.insert(db)
                elementPosition += 1
            }

            return pageId
        }
    }
}
