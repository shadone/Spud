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

/// Denormalized display data captured at vote time. Caller-supplied to
/// `upsertVoteEvent` so the Activity timeline can render entries without
/// joining the (possibly-evicted) post/comment cache.
public struct VoteEventSnapshot: Sendable, Equatable {
    public let title: String?
    public let body: String?
    public let communityName: String?
    public let communityActorId: String?
    public let thumbnailUrl: String?
    public let score: Int64?
}

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

    /// Note: never returns `.downloaded`. That feed is local-only and never
    /// persists a `FeedRecord` (`LemmyService.fetchFeed` returns nil for it, so
    /// `appendFeedPage` is never reached) — there is no column that would decode
    /// to it, so no arm is needed here.
    private static func decodeFeedType(_ record: FeedRecord) -> FeedType? {
        guard let sortType = Lemmy.SortType(rawValue: record.sortType) else {
            logger.error("Unknown sortType '\(record.sortType, privacy: .public)' on feedKey \(record.feedKey, privacy: .public)")
            return nil
        }

        if record.savedOnly {
            return .saved(sortType: sortType)
        }

        if let listingRaw = record.frontpageListingType {
            guard let listingType = Lemmy.ListingType(rawValue: listingRaw) else {
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

    /// Current vote status for the post identified by `serverPostId` from
    /// the account identified by `accountKeychainId`. Used by
    /// `LemmyService.vote(serverPostId:vote:)` to compute the effective
    /// toggle action. Defaults to `.neutral` when no row exists or the
    /// column is `NULL` / unrecognised.
    func postVoteStatus(
        forAccountKeychainId keychainId: String,
        serverPostId: Lemmy.PostID
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
    /// Used by `LemmyService.vote(serverCommentId:vote:)`.
    func commentVoteStatus(
        forAccountKeychainId keychainId: String,
        serverCommentId: Lemmy.CommentID
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

    // MARK: - Vote snapshots

    /// Display snapshot for a post vote event. Returns nil when the post is not
    /// in the local cache (best-effort; the caller silently omits snapshot fields).
    func postVoteSnapshot(
        forAccountKeychainId keychainId: String,
        serverPostId: Lemmy.PostID
    ) async throws -> VoteEventSnapshot? {
        try await writer.read { db -> VoteEventSnapshot? in
            let row = try Row.fetchOne(db, sql: """
                SELECT
                    post.title          AS title,
                    post.thumbnailUrl   AS thumbnailUrl,
                    post.score          AS score,
                    community.name      AS communityName,
                    community.actorId   AS communityActorId
                FROM post
                JOIN account   ON account.id   = post.accountId
                JOIN community ON community.id = post.communityId
                WHERE account.accountKeychainId = ?
                  AND post.postId = ?
                """, arguments: [keychainId, Int64(serverPostId)])
            guard let row else { return nil }
            return VoteEventSnapshot(
                title: row["title"],
                body: nil,
                communityName: row["communityName"],
                communityActorId: row["communityActorId"],
                thumbnailUrl: row["thumbnailUrl"],
                score: row["score"]
            )
        }
    }

    /// Display snapshot for a comment vote event. `title` is the parent post
    /// title; `body` is the comment body. Returns nil when the comment is not in
    /// the local cache (best-effort).
    func commentVoteSnapshot(
        forAccountKeychainId keychainId: String,
        serverCommentId: Lemmy.CommentID
    ) async throws -> VoteEventSnapshot? {
        try await writer.read { db -> VoteEventSnapshot? in
            let row = try Row.fetchOne(db, sql: """
                SELECT
                    comment.body        AS body,
                    post.title          AS title,
                    post.thumbnailUrl   AS thumbnailUrl,
                    comment.score       AS score,
                    community.name      AS communityName,
                    community.actorId   AS communityActorId
                FROM comment
                JOIN post      ON post.id      = comment.postId
                JOIN account   ON account.id   = post.accountId
                JOIN community ON community.id = post.communityId
                WHERE account.accountKeychainId = ?
                  AND comment.localCommentId = ?
                """, arguments: [keychainId, Int64(serverCommentId)])
            guard let row else { return nil }
            return VoteEventSnapshot(
                title: row["title"],
                body: row["body"],
                communityName: row["communityName"],
                communityActorId: row["communityActorId"],
                thumbnailUrl: row["thumbnailUrl"],
                score: row["score"]
            )
        }
    }
}
