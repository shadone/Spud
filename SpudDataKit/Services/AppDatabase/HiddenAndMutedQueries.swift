//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

/// A hidden post, for the "Hidden & Muted" management screen.
public struct HiddenPostListItem: Sendable, Equatable, Identifiable {
    public var id: Int64 {
        serverPostId
    }

    public let serverPostId: Int64
    public let title: String
    public let communityName: String
    public let thumbnailUrl: String?
}

/// A muted community, for the "Hidden & Muted" management screen.
public struct MutedCommunityListItem: Sendable, Equatable, Identifiable {
    public var id: String {
        communityActorId
    }

    public let communityActorId: String
    /// When the mute expires; nil means indefinitely.
    public let mutedUntil: Date?
}

public extension AppDatabase {
    /// The account's hidden posts, most recently hidden first.
    func hiddenPostsSync(forKeychainId keychainId: String) -> [HiddenPostListItem] {
        do {
            return try writer.read { db in
                try Row.fetchAll(db, sql: """
                        SELECT
                            post.postId        AS serverPostId,
                            post.title         AS title,
                            community.name     AS communityName,
                            post.thumbnailUrl  AS thumbnailUrl
                        FROM post
                        JOIN account   ON account.id = post.accountId
                        JOIN community ON community.id = post.communityId
                        WHERE account.accountKeychainId = ?
                          AND post.isHidden = 1
                        ORDER BY post.updatedAt DESC
                    """, arguments: [keychainId])
                    .map { row in
                        HiddenPostListItem(
                            serverPostId: row["serverPostId"],
                            title: row["title"] ?? "",
                            communityName: row["communityName"] ?? "",
                            thumbnailUrl: row["thumbnailUrl"]
                        )
                    }
            }
        } catch {
            logger.error("hiddenPostsSync failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// The account's muted communities, most recently muted first.
    func mutedCommunitiesSync(forKeychainId keychainId: String) -> [MutedCommunityListItem] {
        do {
            return try writer.read { db in
                guard
                    let accountId = try AccountRecord
                    .filter(Column("accountKeychainId") == keychainId)
                    .fetchOne(db)?
                    .id
                else { return [] }

                return try MutedCommunityRecord
                    .filter(Column("accountId") == accountId)
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
                    .map { record in
                        MutedCommunityListItem(
                            communityActorId: record.communityActorId,
                            mutedUntil: record.mutedUntil
                        )
                    }
            }
        } catch {
            logger.error("mutedCommunitiesSync failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }
}
