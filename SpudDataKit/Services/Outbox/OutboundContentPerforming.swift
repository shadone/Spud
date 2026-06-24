//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// Sends an outbound row to the server. Returns the new post's server id for
/// posts (so the pending post screen can swap to the real one); nil for comments.
public protocol OutboundContentPerforming: Sendable {
    func perform(_ record: OutboundContentRecord) async throws -> Int64?
}

public struct LemmyComposerPerformer: OutboundContentPerforming {
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

    public func perform(_ record: OutboundContentRecord) async throws -> Int64? {
        guard let kind = OutboundKind(rawValue: record.kind) else { return nil }
        switch kind {
        case .comment:
            guard let postServerId = record.postServerId else { return nil }
            let response = try await api.createComment(
                postID: Components.Schemas.PostID(postServerId),
                content: record.body,
                parentID: record.parentCommentServerId.map { Components.Schemas.CommentID($0) }
            )
            try await appDatabase.upsertComment(
                from: response.comment_view,
                accountId: accountId,
                siteId: siteId,
                respectsPendingOutbox: false
            )
            return nil
        case .post:
            guard let communityServerId = record.communityServerId else { return nil }
            let trimmedBody = record.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await api.createPost(
                communityID: Components.Schemas.CommunityID(communityServerId),
                name: record.title ?? "",
                url: record.url,
                body: trimmedBody.isEmpty ? nil : trimmedBody,
                nsfw: record.nsfw
            )
            try await appDatabase.upsertPost(
                from: response.post_view,
                accountId: accountId,
                siteId: siteId,
                respectsPendingOutbox: false
            )
            return Int64(response.post_view.post.id)
        }
    }
}
