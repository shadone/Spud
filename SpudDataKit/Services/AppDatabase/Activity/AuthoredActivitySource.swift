//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog

private let logger = Logger.appDatabase

/// One page of the account holder's authored content, mapped for the activity
/// merge.
///
/// Posts are persisted as a side effect of fetching (their rendered rows arrive
/// via the person-post observation, not here); this page only carries the
/// comment items plus the bookkeeping the coordinator needs to advance and clamp
/// the merge frontier.
public struct AuthoredActivityPage: Sendable, Equatable {
    /// The page's comment activity items (`act == .comment`), reverse-chronological.
    public let comments: [ActivityItem]
    /// Oldest post `published` in this page, or nil when the page had no posts.
    /// Used to advance the authored-post merge frontier.
    public let oldestPostPublished: Date?
    /// Oldest comment `published` in this page, or nil when the page had no
    /// comments. Used to advance the authored-comment merge frontier.
    public let oldestCommentPublished: Date?
    /// True when this page returned no posts: the authored-post source is exhausted.
    public let postsExhausted: Bool
    /// True when this page returned no comments: the authored-comment source is exhausted.
    public let commentsExhausted: Bool

    public init(
        comments: [ActivityItem],
        oldestPostPublished: Date?,
        oldestCommentPublished: Date?,
        postsExhausted: Bool,
        commentsExhausted: Bool
    ) {
        self.comments = comments
        self.oldestPostPublished = oldestPostPublished
        self.oldestCommentPublished = oldestCommentPublished
        self.postsExhausted = postsExhausted
        self.commentsExhausted = commentsExhausted
    }
}

/// Pull-based source of the account holder's authored content, paginated one
/// page at a time.
///
/// Injected into ``ActivityCoordinator`` so the merge and pagination can be
/// exercised in tests without a live network. The production conformance
/// (``LemmyAuthoredActivitySource``) wraps `getPersonDetails`.
public protocol AuthoredActivitySource: Sendable {
    /// Fetches (and, for posts, persists) page `page` of the account holder's
    /// authored content. Throws on a network / server failure so the coordinator
    /// can degrade to the local stream rather than fail the whole stream.
    func loadPage(_ page: Int64) async throws -> AuthoredActivityPage
}

/// `AuthoredActivitySource` backed by `LemmyService.fetchPersonContent`
/// (getPersonDetails).
///
/// Always fetches with `.New` so a page is in published-descending order,
/// matching the activity timeline's reverse-chronological ordering. The fetch
/// persists the page's posts (picked up by the person-post observation); the
/// comments are mapped to transient `ActivityItem`s here, mirroring how the
/// profile Comments tab and Search treat their results.
public struct LemmyAuthoredActivitySource: AuthoredActivitySource {
    private let lemmyService: LemmyServiceType
    private let serverPersonId: Lemmy.PersonID

    public init(
        lemmyService: LemmyServiceType,
        serverPersonId: Lemmy.PersonID
    ) {
        self.lemmyService = lemmyService
        self.serverPersonId = serverPersonId
    }

    public func loadPage(_ page: Int64) async throws -> AuthoredActivityPage {
        let response = try await lemmyService.fetchPersonContent(
            serverPersonId: serverPersonId,
            sort: .New,
            page: page
        )

        let comments = response.comments.map(ActivityItem.init(authoredComment:))
        // Compute the oldest published per source rather than relying on the
        // response being perfectly ordered, so the frontier is robust to any
        // server-side ordering quirk.
        return AuthoredActivityPage(
            comments: comments,
            oldestPostPublished: response.posts.map(\.post.publishedAt).min(),
            oldestCommentPublished: response.comments.map(\.comment.publishedAt).min(),
            postsExhausted: response.posts.isEmpty,
            commentsExhausted: response.comments.isEmpty
        )
    }
}

// MARK: - Mapping authored content to ActivityItem

public extension ActivityItem {
    /// Builds a `.post` activity item from a person-post observation row. The
    /// sort key is the post's `published` date. The id (`post-post-<serverId>`)
    /// is distinct from the local `save-post-<serverId>` / `read-post-<serverId>`
    /// ids, so an authored post and a saved/read row for the same post are kept
    /// as separate rows (intended in v1).
    init(authoredPost row: PostListRow) {
        self.init(
            id: "post-post-\(row.serverPostId)",
            act: .post,
            occurredAt: row.published,
            object: .post(row)
        )
    }

    /// Builds a `.comment` activity item from a transient authored `CommentView`.
    /// The comment is not persisted (the profile Comments tab keeps these in
    /// memory), so `ActivityCommentRow.id` is 0; navigation uses the server ids.
    init(authoredComment view: Lemmy.CommentView) {
        let row = ActivityCommentRow(
            id: 0,
            serverCommentId: Int64(view.comment.id),
            body: view.comment.content,
            score: view.comment.score,
            parentPostTitle: view.post.name,
            communityName: view.community.name,
            communityActorId: view.community.apId,
            serverPostId: Int64(view.post.id),
            published: view.comment.publishedAt
        )
        self.init(
            id: "comment-comment-\(row.serverCommentId)",
            act: .comment,
            occurredAt: view.comment.publishedAt,
            object: .comment(row)
        )
    }
}
