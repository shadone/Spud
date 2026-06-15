//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

public extension AppDatabase {
    /// The `lastOpenedAt` recorded for `(account, post)` *before* the current
    /// open is written. Read synchronously during PostDetail bring-up so the
    /// new-comment delta has the prior-visit reference before `recordPostOpened`
    /// overwrites it. nil if never opened or the account/row is missing.
    func lastOpenedAtSync(forKeychainId keychainId: String, serverPostId: Int64) -> Date? {
        do {
            return try writer.read { db -> Date? in
                guard let accountId = try Self.accountRowId(forKeychainId: keychainId, in: db) else {
                    return nil
                }
                return try Self.interaction(accountId: accountId, postServerId: serverPostId, in: db)?.lastOpenedAt
            }
        } catch {
            logger.error("lastOpenedAtSync failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The server-assigned person id for the account, used to exclude the
    /// user's own comments from the new-comment delta. nil for signed-out
    /// accounts (no linked person) or an unknown account.
    func accountPersonServerIdSync(forKeychainId keychainId: String) -> Int64? {
        do {
            return try writer.read { db -> Int64? in
                try Int64.fetchOne(db, sql: """
                    SELECT person.personId
                    FROM account
                    JOIN person ON person.id = account.personId
                    WHERE account.accountKeychainId = ?
                    """, arguments: [keychainId])
            }
        } catch {
            logger.error("accountPersonServerIdSync failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Builds an interaction snapshot (+ current comment count) from the cached
    /// `post` row, joining community + creator. nil if the post row is absent.
    /// `instanceHost` is derived from the community's federation actor id.
    func postInteractionSnapshotSync(postRowId: Int64) -> (snapshot: PostInteractionSnapshot, commentCount: Int64)? {
        do {
            return try writer.read { db -> (PostInteractionSnapshot, Int64)? in
                guard let row = try Row.fetchOne(db, sql: """
                        SELECT
                            post.title            AS title,
                            post.thumbnailUrl     AS thumbnailUrl,
                            post.numberOfComments AS numberOfComments,
                            community.name        AS communityName,
                            community.actorId     AS communityActorId,
                            creator.name          AS creatorName
                        FROM post
                        JOIN community ON community.id = post.communityId
                        JOIN person AS creator ON creator.id = post.creatorId
                        WHERE post.id = ?
                    """, arguments: [postRowId])
                else {
                    return nil
                }
                let communityActorId: String? = row["communityActorId"]
                let instanceHost = communityActorId.flatMap { URL(string: $0)?.host } ?? ""
                let snapshot = PostInteractionSnapshot(
                    titleSnapshot: row["title"] ?? "",
                    communityName: row["communityName"] ?? "",
                    instanceHost: instanceHost,
                    thumbnailUrl: row["thumbnailUrl"],
                    author: row["creatorName"]
                )
                let commentCount: Int64 = row["numberOfComments"] ?? 0
                return (snapshot, commentCount)
            }
        } catch {
            logger.error("postInteractionSnapshotSync failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
