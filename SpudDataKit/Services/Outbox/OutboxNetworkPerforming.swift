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
                let r = try await api.likePost(postID: Components.Schemas.PostID(op.entityServerId), status: status)
                try await appDatabase.upsertPost(from: r.post_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .comment:
                let r = try await api.likeComment(commentID: Components.Schemas.CommentID(op.entityServerId), status: status)
                try await appDatabase.upsertComment(from: r.comment_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            }
        case let .save(value):
            switch op.entityType {
            case .post:
                let r = try await api.savePost(postID: Components.Schemas.PostID(op.entityServerId), save: value)
                try await appDatabase.upsertPost(from: r.post_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .comment:
                let r = try await api.saveComment(commentID: Components.Schemas.CommentID(op.entityServerId), save: value)
                try await appDatabase.upsertComment(from: r.comment_view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            }
        case let .hide(value):
            _ = try await api.hidePost(postIDs: [Components.Schemas.PostID(op.entityServerId)], hide: value)
            // No entity returned; optimistic write stands.
        }
    }
}
