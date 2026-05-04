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

public extension AppDatabase {
    /// Reconstructs the `FeedType` for an existing `feedKey` from the persisted
    /// FeedRecord columns (`frontpageListingType` / `communityName` /
    /// `communityInstanceActorId` / `sortType`). Returns nil when no row is
    /// found or the row's columns are inconsistent. Stage 3d.1 replacement
    /// for `LemmyService.resolveLegacyFeed(feedKey:)`.
    func feedType(forFeedKey feedKey: String) async throws -> FeedType? {
        try await writer.read { db in
            guard
                let record = try FeedRecord
                .filter(Column("feedKey") == feedKey)
                .fetchOne(db)
            else { return nil }
            return Self.decodeFeedType(record)
        }
    }

    private static func decodeFeedType(_ record: FeedRecord) -> FeedType? {
        guard let sortType = Components.Schemas.SortType(rawValue: record.sortType) else {
            logger.error("Unknown sortType '\(record.sortType, privacy: .public)' on feedKey \(record.feedKey, privacy: .public)")
            return nil
        }

        if let listingRaw = record.frontpageListingType {
            guard let listingType = Components.Schemas.ListingType(rawValue: listingRaw) else {
                logger.error("Unknown frontpageListingType '\(listingRaw, privacy: .public)' on feedKey \(record.feedKey, privacy: .public)")
                return nil
            }
            return .frontpage(listingType: listingType, sortType: sortType)
        }

        guard
            let communityName = record.communityName,
            let actorIdRaw = record.communityInstanceActorId,
            let instance = InstanceActorId(from: actorIdRaw)
        else {
            logger.error("Incomplete community FeedRecord for feedKey \(record.feedKey, privacy: .public)")
            return nil
        }
        return .community(
            communityName: communityName,
            instance: instance,
            sortType: sortType
        )
    }

    /// Current vote status for the post identified by `serverPostId` from the
    /// account identified by `accountKeychainId`. Stage 3d.1 replacement for
    /// the Core Data lookup that `LemmyService.vote(serverPostId:vote:)`
    /// previously used to compute the effective toggle action. Defaults to
    /// `.neutral` when no row exists or the column is `NULL` / unrecognised.
    func postVoteStatus(
        forAccountKeychainId keychainId: String,
        serverPostId: Components.Schemas.PostID
    ) async throws -> VoteStatus {
        let raw = try await writer.read { db -> Int64? in
            try Int64.fetchOne(db, sql: """
                    SELECT post.voteStatus
                    FROM post
                    JOIN account ON account.id = post.accountId
                    WHERE account.accountKeychainId = ?
                      AND post.postId = ?
                """, arguments: [keychainId, Int64(serverPostId)])
        }
        return Self.decodeVoteStatus(raw)
    }

    /// Current vote status for the comment identified by its server-side
    /// `localCommentId` from the account identified by `accountKeychainId`.
    /// Stage 3d.1 replacement for the Core Data lookup that
    /// `LemmyService.vote(serverCommentId:vote:)` previously used.
    func commentVoteStatus(
        forAccountKeychainId keychainId: String,
        serverCommentId: Components.Schemas.CommentID
    ) async throws -> VoteStatus {
        let raw = try await writer.read { db -> Int64? in
            try Int64.fetchOne(db, sql: """
                    SELECT comment.voteStatus
                    FROM comment
                    JOIN post    ON post.id = comment.postId
                    JOIN account ON account.id = post.accountId
                    WHERE account.accountKeychainId = ?
                      AND comment.localCommentId = ?
                """, arguments: [keychainId, Int64(serverCommentId)])
        }
        return Self.decodeVoteStatus(raw)
    }

    private static func decodeVoteStatus(_ raw: Int64?) -> VoteStatus {
        switch raw {
        case 1: return .up
        case 0: return .down
        default: return .neutral
        }
    }
}
