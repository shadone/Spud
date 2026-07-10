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
        // The neutral vote/save/hide/delete/follow endpoints take the entity's
        // `Int64` server id directly and return the neutral view.
        let id = op.entityServerId
        switch op.desiredState {
        case let .vote(status):
            switch op.entityType {
            case .post:
                let view = try await api.votePostNeutral(id: id, direction: VoteDirection(status))
                try await appDatabase.upsertPost(from: view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .comment:
                let view = try await api.voteCommentNeutral(id: id, direction: VoteDirection(status))
                try await appDatabase.upsertComment(from: view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .community:
                break // vote never targets a community; nothing to send.
            }
        case let .save(value):
            switch op.entityType {
            case .post:
                let view = try await api.savePostNeutral(id: id, saved: value)
                try await appDatabase.upsertPost(from: view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .comment:
                let view = try await api.saveCommentNeutral(id: id, saved: value)
                try await appDatabase.upsertComment(from: view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .community:
                break // save never targets a community; nothing to send.
            }
        case let .hide(value):
            // No entity returned; optimistic write stands.
            try await api.hidePostNeutral(id: id, hidden: value)
        case let .delete(value):
            // Delete/restore of the user's own post or comment.
            switch op.entityType {
            case .post:
                let view = try await api.deletePostNeutral(id: id, deleted: value)
                try await appDatabase.upsertPost(from: view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .comment:
                let view = try await api.deleteCommentNeutral(id: id, deleted: value)
                try await appDatabase.upsertComment(from: view, accountId: accountId, siteId: siteId, respectsPendingOutbox: false)
            case .community:
                break // delete never targets a community; nothing to send.
            }
        case let .subscribe(value):
            // Subscribe/unsubscribe a community. `followCommunityNeutral` returns
            // the authoritative CommunityView (accepted or pending); mirror it so
            // the optimistic pending is upgraded to the server's answer (and the
            // followed-communities junction is synced by the importer).
            switch op.entityType {
            case .community:
                let view = try await api.followCommunityNeutral(id: id, follow: value)
                // Authoritative post-send mirror: bypass the pending-outbox guard
                // so the server's confirmed subscribed state overrides the still-
                // pending optimistic projection.
                try await appDatabase.upsertCommunity(
                    from: view,
                    accountId: accountId,
                    respectsPendingOutbox: false
                )
            case .post, .comment:
                break // subscribe only targets a community; nothing to send.
            }
        }
    }
}
