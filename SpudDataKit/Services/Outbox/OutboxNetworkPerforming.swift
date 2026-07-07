//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// Sends a single ``OutboxOperation`` to the server and, on success, reconciles
/// the authoritative server response into the database.
public protocol OutboxNetworkPerforming: Sendable {
    /// Sends `op` to the server. On success, reconciles authoritative state into
    /// the database (vote/save) or leaves the optimistic write standing (hide).
    /// Throws the underlying error on failure for the caller to classify.
    func perform(_ op: OutboxOperation) async throws
}

/// Production implementation that calls ``LemmyApi`` and reconciles the response
/// back into ``AppDatabase`` via the authoritative (non-outbox-guarded) import path.
public struct LemmyOutboxPerformer: OutboxNetworkPerforming {
    let api: LemmyApi
    let appDatabase: AppDatabase
    let accountId: Int64
    let siteId: Int64

    public init(api: LemmyApi, appDatabase: AppDatabase, accountId: Int64, siteId: Int64) {
        self.api = api
        self.appDatabase = appDatabase
        self.accountId = accountId
        self.siteId = siteId
    }

    public func perform(_ op: OutboxOperation) async throws {
        switch op.desiredState {
        case let .vote(status):
            switch op.entityType {
            case .post:
                let r = try await api.likePost(postID: Lemmy.PostID(op.entityServerId), status: status)
                try await appDatabase.upsertPost(from: r.post_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .comment:
                let r = try await api.likeComment(commentID: Lemmy.CommentID(op.entityServerId), status: status)
                try await appDatabase.upsertComment(from: r.comment_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .community:
                break // vote never targets a community; nothing to send.
            }
        case let .save(value):
            switch op.entityType {
            case .post:
                let r = try await api.savePost(postID: Lemmy.PostID(op.entityServerId), save: value)
                try await appDatabase.upsertPost(from: r.post_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .comment:
                let r = try await api.saveComment(commentID: Lemmy.CommentID(op.entityServerId), save: value)
                try await appDatabase.upsertComment(from: r.comment_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .community:
                break // save never targets a community; nothing to send.
            }
        case let .hide(value):
            // No entity returned; optimistic write stands.
            _ = try await api.hidePost(postIDs: [Lemmy.PostID(op.entityServerId)], hide: value)
        case let .delete(value):
            // Delete/restore of the user's own post or comment.
            switch op.entityType {
            case .post:
                let r = try await api.deletePost(postID: Lemmy.PostID(op.entityServerId), deleted: value)
                try await appDatabase.upsertPost(from: r.post_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .comment:
                let r = try await api.deleteComment(commentID: Lemmy.CommentID(op.entityServerId), deleted: value)
                try await appDatabase.upsertComment(from: r.comment_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .community:
                break // delete never targets a community; nothing to send.
            }
        case let .subscribe(value):
            // Subscribe/unsubscribe a community. `followCommunity` returns the
            // authoritative CommunityView (Subscribed or Pending); mirror it so
            // the optimistic Pending is upgraded to the server's answer (and the
            // followed-communities junction is synced by the importer).
            switch op.entityType {
            case .community:
                let r = try await api.followCommunity(
                    communityID: Lemmy.CommunityID(op.entityServerId),
                    follow: value
                )
                // Authoritative post-send mirror: bypass the pending-outbox guard
                // so the server's confirmed subscribed state overrides the still-
                // pending optimistic projection.
                try await appDatabase.upsertCommunity(
                    from: r.community_view,
                    accountId: accountId,
                    respectsPendingOutbox: false
                )
            case .post, .comment:
                break // subscribe only targets a community; nothing to send.
            }
        }
    }
}
