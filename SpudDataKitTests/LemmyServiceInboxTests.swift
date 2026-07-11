//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import HTTPTypes
import LemmyKit
import OpenAPIRuntime
import Testing
@testable import SpudDataKit

// Replies/mentions still ride the generated v3 inbox shapes (`CommentReplyView`
// et al. have no neutral counterpart), so these payload helpers are built on
// `Components.Schemas.*` via the `V3` fakes.
private typealias CommentReply = Lemmy.CommentReply
private typealias CommentReplyView = Lemmy.CommentReplyView
private typealias GetRepliesResponse = Lemmy.GetRepliesResponse
private typealias GetUnreadCountResponse = Lemmy.GetUnreadCountResponse
private typealias PrivateMessageResponse = Lemmy.PrivateMessageResponse
private typealias CommentReplyResponse = Lemmy.CommentReplyResponse

/// Stub transport returning canned JSON keyed by operation id, recording which
/// operations were hit. Each operation maps to a pre-encoded body.
private final class StubInboxTransport: ClientTransport, @unchecked Sendable {
    private var bodies: [String: Data] = [:]
    private(set) var sentOperationIds: [String] = []

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        return encoder
    }

    func register(_ operationId: String, _ value: some Encodable) throws {
        bodies[operationId] = try Self.encoder().encode(value)
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        sentOperationIds.append(operationID)
        guard let data = bodies[operationID] else {
            throw UnexpectedOperation(operationID: operationID)
        }
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(data))
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

@MainActor
struct LemmyServiceInboxTests {
    private let keychainId = "keychain-1"

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    @discardableResult
    private func seedAccountAndSite() async throws -> Int64 {
        let keychainId = keychainId
        return try await appDatabase.writer.write { db -> Int64 in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return account.id!
        }
    }

    private func replyView(id: Lemmy.CommentReplyID, read: Bool) -> CommentReplyView {
        let comment = V3.comment(id: 5)
        return CommentReplyView(
            comment_reply: CommentReply(
                id: id,
                recipient_id: 1,
                comment_id: comment.id,
                read: read,
                published: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            comment: comment,
            creator: V3.person(),
            post: V3.post(),
            community: V3.community(),
            recipient: V3.person(),
            counts: V3.commentAggregates(commentId: comment.id, childCount: 0),
            creator_banned_from_community: false,
            banned_from_community: false,
            creator_is_moderator: false,
            creator_is_admin: false,
            subscribed: .NotSubscribed,
            saved: false,
            creator_blocked: false
        )
    }

    /// A generated v3 `PrivateMessageView` for the `createPrivateMessage` stub
    /// payload (`PrivateMessageResponse.private_message_view`); the neutral
    /// endpoint decodes it and maps to `Lemmy.PrivateMessageView`.
    private func messageView(
        id: Lemmy.PrivateMessageID,
        creator: Components.Schemas.Person,
        recipient: Components.Schemas.Person
    ) -> Components.Schemas.PrivateMessageView {
        V3.privateMessageView(id: id, creator: creator, recipient: recipient, content: "hi there")
    }

    // MARK: unread count

    @Test
    func unreadCountMapsThrough() async throws {
        try await seedAccountAndSite()

        let transport = StubInboxTransport()
        try transport.register(
            "getUnreadCount",
            GetUnreadCountResponse(replies: 3, mentions: 2, private_messages: 5)
        )
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        let count = try await service.unreadCount()

        #expect(transport.sentOperationIds.contains("getUnreadCount"))
        #expect(count.replies == 3)
        #expect(count.mentions == 2)
        #expect(count.privateMessages == 5)
        #expect(count.total == 10)
    }

    @Test
    func unreadCountSignedOutThrowsAndSkipsApi() async throws {
        try await seedAccountAndSite()

        let transport = StubInboxTransport()
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        do {
            _ = try await service.unreadCount()
            Issue.record("Expected unreadCount to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }
        #expect(transport.sentOperationIds.isEmpty)
    }

    // MARK: replies

    @Test
    func fetchRepliesMapsThrough() async throws {
        try await seedAccountAndSite()

        let transport = StubInboxTransport()
        try transport.register(
            "getReplies",
            GetRepliesResponse(replies: [
                replyView(id: 10, read: false),
                replyView(id: 11, read: true),
            ])
        )
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        let response = try await service.fetchReplies(unreadOnly: false, page: 1)

        #expect(transport.sentOperationIds.contains("getReplies"))
        #expect(response.replies.count == 2)
        #expect(response.replies.first?.comment_reply.id == 10)
    }

    @Test
    func fetchRepliesSignedOutThrows() async throws {
        try await seedAccountAndSite()

        let transport = StubInboxTransport()
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        do {
            _ = try await service.fetchReplies(unreadOnly: false, page: 1)
            Issue.record("Expected fetchReplies to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }
        #expect(transport.sentOperationIds.isEmpty)
    }

    // MARK: mark read

    @Test
    func markReplyAsReadHitsApi() async throws {
        try await seedAccountAndSite()

        let transport = StubInboxTransport()
        try transport.register(
            "markCommentReplyAsRead",
            CommentReplyResponse(comment_reply_view: replyView(id: 10, read: true))
        )
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.markReplyAsRead(commentReplyId: 10, read: true)

        #expect(transport.sentOperationIds.contains("markCommentReplyAsRead"))
    }

    // MARK: send private message

    @Test
    func sendPrivateMessageHitsApiAndReturnsView() async throws {
        try await seedAccountAndSite()

        let creator = V3.person(id: 7, name: "alice")
        let recipient = V3.person(id: 1, name: "me")

        let transport = StubInboxTransport()
        try transport.register(
            "createPrivateMessage",
            PrivateMessageResponse(private_message_view: messageView(id: 99, creator: creator, recipient: recipient))
        )
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        let view = try await service.sendPrivateMessage(content: "hi there", recipientId: 7)

        #expect(transport.sentOperationIds.contains("createPrivateMessage"))
        #expect(view.privateMessage.id == 99)
        #expect(view.privateMessage.content == "hi there")
    }

    @Test
    func sendPrivateMessageSignedOutThrowsAndSkipsApi() async throws {
        try await seedAccountAndSite()

        let transport = StubInboxTransport()
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        do {
            _ = try await service.sendPrivateMessage(content: "hi", recipientId: 7)
            Issue.record("Expected sendPrivateMessage to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }
        #expect(transport.sentOperationIds.isEmpty)
    }
}
