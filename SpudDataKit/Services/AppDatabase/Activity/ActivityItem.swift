//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public enum ActivityAct: String, Sendable, CaseIterable {
    case upvote, downvote, comment, post, save, read, seen, hide
}

public enum ActivityFilterType: String, Sendable, CaseIterable {
    case post, comment, save, vote, read, seen, hide

    /// Maps an `ActivityAct` to its filter bucket.
    /// Upvote and downvote both map to `.vote`; all others are 1:1.
    public static func of(_ act: ActivityAct) -> ActivityFilterType {
        switch act {
        case .upvote, .downvote: .vote
        case .comment: .comment
        case .post: .post
        case .save: .save
        case .read: .read
        case .seen: .seen
        case .hide: .hide
        }
    }
}

public enum ActivityObject: Sendable, Equatable {
    case post(PostListRow)
    case comment(ActivityCommentRow)
}

public struct ActivityCommentRow: Sendable, Equatable, Identifiable {
    /// GRDB row id of the live `comment` row, or 0 when only a voteEvent snapshot is available.
    public let id: Int64
    public let serverCommentId: Int64
    public let body: String
    public let score: Int64
    public let parentPostTitle: String
    public let communityName: String
    public let communityActorId: String?
    /// Server-assigned post id of the parent post. nil when derived solely from a voteEvent snapshot.
    public let serverPostId: Int64?
    public let published: Date

    public init(
        id: Int64,
        serverCommentId: Int64,
        body: String,
        score: Int64,
        parentPostTitle: String,
        communityName: String,
        communityActorId: String?,
        serverPostId: Int64?,
        published: Date
    ) {
        self.id = id
        self.serverCommentId = serverCommentId
        self.body = body
        self.score = score
        self.parentPostTitle = parentPostTitle
        self.communityName = communityName
        self.communityActorId = communityActorId
        self.serverPostId = serverPostId
        self.published = published
    }
}

public struct ActivityItem: Sendable, Equatable, Identifiable {
    /// Stable per-source identifier: `"\(act.rawValue)-\(object-kind)-\(serverId)"`.
    ///
    /// The same post can produce multiple `ActivityItem`s (e.g. "read-post-42" and
    /// "save-post-42") because each source tracks a distinct user action.
    public let id: String
    public let act: ActivityAct
    /// Unified sort key. Each source uses its own timestamp:
    /// - `.read` → `postInteraction.lastOpenedAt`
    /// - `.seen` → `postInteraction.lastSeenAt`
    /// - `.save` (post) → `coalesce(lastOpenedAt, lastSeenAt, post.published)` (Phase-1 proxy; no savedAt column)
    /// - `.save` (comment) → `comment.published`
    /// - `.hide` → `coalesce(lastOpenedAt, lastSeenAt, post.published)` (Phase-1 proxy)
    /// - `.upvote`/`.downvote` → `voteEvent.votedAt`
    public let occurredAt: Date
    public let object: ActivityObject

    public init(id: String, act: ActivityAct, occurredAt: Date, object: ActivityObject) {
        self.id = id
        self.act = act
        self.occurredAt = occurredAt
        self.object = object
    }
}
