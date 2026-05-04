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
    /// Stream of all real (non-service) accounts ordered by sign-in state then
    /// keychain id. The first element is emitted as soon as the observation
    /// starts; further elements arrive whenever the underlying rows change.
    func observeAccounts() -> AsyncStream<[AccountRecord]> {
        let observation = ValueObservation
            .tracking { db in
                try AccountRecord
                    .filter(Column("isServiceAccount") == false)
                    .order(
                        Column("isSignedOutAccountType").asc,
                        Column("accountKeychainId").asc
                    )
                    .fetchAll(db)
            }
            .removeDuplicates()
        return makeStream(observation: observation)
    }

    /// Stream of the current default account, or nil if none is marked
    /// default. Yields immediately on subscription and again on each change.
    func observeDefaultAccount() -> AsyncStream<AccountRecord?> {
        let observation = ValueObservation
            .tracking { db in
                try AccountRecord
                    .filter(Column("isDefault") == true)
                    .filter(Column("isServiceAccount") == false)
                    .fetchOne(db)
            }
            .removeDuplicates()
        return makeStream(observation: observation)
    }

    /// Stream of accounts for a specific site, ordered by keychain id.
    func observeAccounts(forSiteId siteId: Int64) -> AsyncStream<[AccountRecord]> {
        let observation = ValueObservation
            .tracking { db in
                try AccountRecord
                    .filter(Column("siteId") == siteId)
                    .filter(Column("isServiceAccount") == false)
                    .order(Column("accountKeychainId").asc)
                    .fetchAll(db)
            }
            .removeDuplicates()
        return makeStream(observation: observation)
    }

    /// Stream of a single site row identified by primary key. Yields nil if
    /// the row no longer exists.
    func observeSite(id siteId: Int64) -> AsyncStream<SiteRecord?> {
        let observation = ValueObservation
            .tracking { db in
                try SiteRecord.fetchOne(db, key: siteId)
            }
            .removeDuplicates()
        return makeStream(observation: observation)
    }

    /// Stream of a single post row identified by primary key. Yields nil if
    /// the row no longer exists.
    func observePost(id postRowId: Int64) -> AsyncStream<PostRecord?> {
        let observation = ValueObservation
            .tracking { db in
                try PostRecord.fetchOne(db, key: postRowId)
            }
            .removeDuplicates()
        return makeStream(observation: observation)
    }

    /// Stream of posts in a feed in display order. Walks page → pageElement →
    /// post and orders by (page.position, pageElement.position).
    func observePostsInFeed(feedId: Int64) -> AsyncStream<[PostRecord]> {
        let observation = ValueObservation
            .tracking { db in
                try PostRecord.fetchAll(db, sql: """
                        SELECT post.*
                        FROM post
                        JOIN pageElement ON pageElement.postId = post.id
                        JOIN page ON page.id = pageElement.pageId
                        WHERE page.feedId = ?
                        ORDER BY page.position ASC, pageElement.position ASC
                    """, arguments: [feedId])
            }
            .removeDuplicates()
        return makeStream(observation: observation)
    }

    /// Stream of comment-tree rows for a (post, sortType) pair, in display
    /// order. Each row pairs the element (which carries position/depth and
    /// "load more" placeholders) with its backing comment row, if any.
    func observeComments(
        forPostRowId postRowId: Int64,
        sortType: String
    ) -> AsyncStream<[CommentTreeRow]> {
        let observation = ValueObservation
            .tracking { db in
                let elements = try CommentElementRecord
                    .filter(Column("postId") == postRowId)
                    .filter(Column("sortType") == sortType)
                    .order(Column("position").asc)
                    .fetchAll(db)

                let commentIds = elements.compactMap(\.commentId)
                let comments = try CommentRecord
                    .filter(commentIds.contains(Column("id")))
                    .fetchAll(db)
                let commentsById = Dictionary(
                    uniqueKeysWithValues: comments.compactMap { c in
                        c.id.map { ($0, c) }
                    }
                )

                return elements.map { element in
                    CommentTreeRow(
                        element: element,
                        comment: element.commentId.flatMap { commentsById[$0] }
                    )
                }
            }
            .removeDuplicates()
        return makeStream(observation: observation)
    }

    /// Stream of communities followed by an account, ordered by community
    /// name (case-insensitive).
    func observeFollowedCommunities(forAccountId accountId: Int64) -> AsyncStream<[CommunityRecord]> {
        let observation = ValueObservation
            .tracking { db in
                try CommunityRecord.fetchAll(db, sql: """
                        SELECT community.*
                        FROM community
                        JOIN accountFollowedCommunity AS afc
                            ON afc.communityId = community.id
                        WHERE afc.accountId = ?
                        ORDER BY LOWER(community.name) ASC
                    """, arguments: [accountId])
            }
            .removeDuplicates()
        return makeStream(observation: observation)
    }

    private func makeStream<Value: Sendable & Equatable>(
        observation: ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Fetch<Value>>>
    ) -> AsyncStream<Value> {
        AsyncStream { continuation in
            let cancellable = observation.start(in: writer) { error in
                logger.error("ValueObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}

/// Pair returned by `observeComments(forPostRowId:sortType:)`. The element
/// carries position/depth and may represent a "load more" placeholder, in
/// which case `comment` is nil.
public struct CommentTreeRow: Sendable, Equatable {
    public let element: CommentElementRecord
    public let comment: CommentRecord?

    public init(element: CommentElementRecord, comment: CommentRecord?) {
        self.element = element
        self.comment = comment
    }
}
