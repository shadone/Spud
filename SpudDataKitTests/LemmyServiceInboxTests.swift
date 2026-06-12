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
import XCTest
@testable import SpudDataKit

private typealias Person = Components.Schemas.Person
private typealias Community = Components.Schemas.Community
private typealias Post = Components.Schemas.Post
private typealias Comment = Components.Schemas.Comment
private typealias CommentAggregates = Components.Schemas.CommentAggregates
private typealias CommentReply = Components.Schemas.CommentReply
private typealias CommentReplyView = Components.Schemas.CommentReplyView
private typealias GetRepliesResponse = Components.Schemas.GetRepliesResponse
private typealias GetUnreadCountResponse = Components.Schemas.GetUnreadCountResponse
private typealias PrivateMessage = Components.Schemas.PrivateMessage
private typealias PrivateMessageView = Components.Schemas.PrivateMessageView
private typealias PrivateMessageResponse = Components.Schemas.PrivateMessageResponse
private typealias CommentReplyResponse = Components.Schemas.CommentReplyResponse

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

final class LemmyServiceInboxTests: XCTestCase {
    private let keychainId = "keychain-1"

    private var appDatabase: AppDatabase!

    override func setUpWithError() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    override func tearDown() {
        appDatabase = nil
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

    private func makeService(
        accountIsSignedOut: Bool,
        transport: any ClientTransport
    ) -> LemmyService {
        let api = LemmyApi(
            instanceUrl: URL(string: "https://example.com")!,
            credential: accountIsSignedOut ? nil : LemmyCredential(jwt: "fake-jwt"),
            transport: transport
        )
        return LemmyService(
            accountKeychainId: keychainId,
            accountIsSignedOut: accountIsSignedOut,
            appDatabase: appDatabase,
            api: api
        )
    }

    private func replyView(id: Components.Schemas.CommentReplyID, read: Bool) -> CommentReplyView {
        let person = Person.fake
        let community = Community.fake
        let post = Post.fake(creator: person, community: community)
        let comment = Comment.fake(id: 5, post: post, creator: person, parent: .root)
        return CommentReplyView(
            comment_reply: CommentReply(
                id: id,
                recipient_id: 1,
                comment_id: comment.id,
                read: read,
                published: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            comment: comment,
            creator: person,
            post: post,
            community: community,
            recipient: person,
            counts: CommentAggregates.fake(commentId: comment.id, childCount: 0),
            creator_banned_from_community: false,
            banned_from_community: false,
            creator_is_moderator: false,
            creator_is_admin: false,
            subscribed: .NotSubscribed,
            saved: false,
            creator_blocked: false
        )
    }

    private func messageView(id: Components.Schemas.PrivateMessageID, creator: Person, recipient: Person) -> PrivateMessageView {
        PrivateMessageView(
            private_message: PrivateMessage(
                id: id,
                creator_id: creator.id,
                recipient_id: recipient.id,
                content: "hi there",
                deleted: false,
                read: false,
                published: Date(timeIntervalSince1970: 1_700_000_000),
                ap_id: "https://example.com/pm/\(id)",
                local: true
            ),
            creator: creator,
            recipient: recipient
        )
    }

    // MARK: unread count

    func testUnreadCountMapsThrough() async throws {
        try await seedAccountAndSite()

        let transport = StubInboxTransport()
        try transport.register(
            "getUnreadCount",
            GetUnreadCountResponse(replies: 3, mentions: 2, private_messages: 5)
        )
        let service = makeService(accountIsSignedOut: false, transport: transport)

        let count = try await service.unreadCount()

        XCTAssertTrue(transport.sentOperationIds.contains("getUnreadCount"))
        XCTAssertEqual(count.replies, 3)
        XCTAssertEqual(count.mentions, 2)
        XCTAssertEqual(count.privateMessages, 5)
        XCTAssertEqual(count.total, 10)
    }

    func testUnreadCountSignedOutThrowsAndSkipsApi() async throws {
        try await seedAccountAndSite()

        let transport = StubInboxTransport()
        let service = makeService(accountIsSignedOut: true, transport: transport)

        do {
            _ = try await service.unreadCount()
            XCTFail("Expected unreadCount to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }
        XCTAssertTrue(transport.sentOperationIds.isEmpty)
    }

    // MARK: replies

    func testFetchRepliesMapsThrough() async throws {
        try await seedAccountAndSite()

        let transport = StubInboxTransport()
        try transport.register(
            "getReplies",
            GetRepliesResponse(replies: [
                replyView(id: 10, read: false),
                replyView(id: 11, read: true),
            ])
        )
        let service = makeService(accountIsSignedOut: false, transport: transport)

        let response = try await service.fetchReplies(unreadOnly: false, page: 1)

        XCTAssertTrue(transport.sentOperationIds.contains("getReplies"))
        XCTAssertEqual(response.replies.count, 2)
        XCTAssertEqual(response.replies.first?.comment_reply.id, 10)
    }

    func testFetchRepliesSignedOutThrows() async throws {
        try await seedAccountAndSite()

        let transport = StubInboxTransport()
        let service = makeService(accountIsSignedOut: true, transport: transport)

        do {
            _ = try await service.fetchReplies(unreadOnly: false, page: 1)
            XCTFail("Expected fetchReplies to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }
        XCTAssertTrue(transport.sentOperationIds.isEmpty)
    }

    // MARK: mark read

    func testMarkReplyAsReadHitsApi() async throws {
        try await seedAccountAndSite()

        let transport = StubInboxTransport()
        try transport.register(
            "markCommentReplyAsRead",
            CommentReplyResponse(comment_reply_view: replyView(id: 10, read: true))
        )
        let service = makeService(accountIsSignedOut: false, transport: transport)

        try await service.markReplyAsRead(commentReplyId: 10, read: true)

        XCTAssertTrue(transport.sentOperationIds.contains("markCommentReplyAsRead"))
    }

    // MARK: send private message

    func testSendPrivateMessageHitsApiAndReturnsView() async throws {
        try await seedAccountAndSite()

        var creator = Person.fake
        creator.id = 7
        creator.name = "alice"
        var recipient = Person.fake
        recipient.id = 1
        recipient.name = "me"

        let transport = StubInboxTransport()
        try transport.register(
            "createPrivateMessage",
            PrivateMessageResponse(private_message_view: messageView(id: 99, creator: creator, recipient: recipient))
        )
        let service = makeService(accountIsSignedOut: false, transport: transport)

        let view = try await service.sendPrivateMessage(content: "hi there", recipientId: 7)

        XCTAssertTrue(transport.sentOperationIds.contains("createPrivateMessage"))
        XCTAssertEqual(view.private_message.id, 99)
        XCTAssertEqual(view.private_message.content, "hi there")
    }

    func testSendPrivateMessageSignedOutThrowsAndSkipsApi() async throws {
        try await seedAccountAndSite()

        let transport = StubInboxTransport()
        let service = makeService(accountIsSignedOut: true, transport: transport)

        do {
            _ = try await service.sendPrivateMessage(content: "hi", recipientId: 7)
            XCTFail("Expected sendPrivateMessage to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }
        XCTAssertTrue(transport.sentOperationIds.isEmpty)
    }
}
