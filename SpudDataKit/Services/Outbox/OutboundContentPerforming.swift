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
            let response: Lemmy.CommentResponse
            if let editCommentServerId = record.editCommentServerId {
                // Edit of an existing comment: update the body in place.
                response = try await api.editComment(
                    commentID: Lemmy.CommentID(editCommentServerId),
                    content: record.body
                )
            } else {
                // Create a new comment / reply.
                guard let postServerId = record.postServerId else { return nil }
                response = try await api.createComment(
                    postID: Lemmy.PostID(postServerId),
                    content: record.body,
                    parentID: record.parentCommentServerId.map { Lemmy.CommentID($0) }
                )
            }
            try await appDatabase.upsertComment(
                from: response.comment_view,
                accountId: accountId,
                siteId: siteId,
                respectsPendingOutbox: false
            )
            return nil
        case .post:
            let trimmedBody = record.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let response: Lemmy.PostResponse
            if let editPostServerId = record.editPostServerId {
                // Edit of an existing post: update title/url/body/nsfw in place.
                response = try await api.editPost(
                    postID: Lemmy.PostID(editPostServerId),
                    name: record.title,
                    url: record.url,
                    body: trimmedBody.isEmpty ? nil : trimmedBody,
                    nsfw: record.nsfw
                )
            } else {
                // Create a new post.
                guard let communityServerId = record.communityServerId else { return nil }
                response = try await api.createPost(
                    communityID: Lemmy.CommunityID(communityServerId),
                    name: record.title ?? "",
                    url: record.url,
                    body: trimmedBody.isEmpty ? nil : trimmedBody,
                    nsfw: record.nsfw
                )
            }
            try await appDatabase.upsertPost(
                from: response.post_view,
                accountId: accountId,
                siteId: siteId,
                respectsPendingOutbox: false
            )
            return Int64(response.post_view.post.id)
        case .directMessage:
            // Send the private message. Each createPrivateMessage call makes a
            // NEW server message — there is no server-side dedup. Unlike the
            // `.comment` create case we therefore deliberately do NOT run a
            // create-dedup block (a matching prior message must not short-circuit
            // a fresh send): the only guard against double-sending the same row is
            // the ComposerOutboxService `inFlight` reservation, which already
            // prevents a concurrent drain from re-sending the same clientToken.
            // A DM row with no recipient can never be sent. Returning nil here
            // would let the generic success path DELETE the row — silently
            // losing the user's message. Throw a permanent error instead so the
            // outbox parks it as `.failed` (content kept). This is a data
            // invariant violation (the send path always supplies a recipient),
            // not a transient condition, hence `.invalidContent` (permanent).
            guard let recipientServerPersonId = record.recipientServerPersonId else {
                throw LemmyServiceError.invalidContent(
                    description: "Direct-message outbound row \(record.clientToken) has no recipient"
                )
            }
            let response = try await api.createPrivateMessage(
                content: record.body,
                recipientID: Lemmy.PersonID(recipientServerPersonId)
            )
            // Import the confirmed message into the persistent store
            // (source of truth). The importer resolves the account's siteId
            // internally and upserts both participants + the message row keyed on
            // (accountId, serverMessageId); the generic success path then deletes
            // this outbound row.
            try await appDatabase.upsertPrivateMessages(
                views: [response.private_message_view],
                accountId: accountId
            )
            return nil
        }
    }
}
