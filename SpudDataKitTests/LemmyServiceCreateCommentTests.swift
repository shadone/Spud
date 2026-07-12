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

private typealias CommentResponse = Lemmy.CommentResponse

/// Stub `ClientTransport` that returns a canned JSON response for the
/// `createComment` operation and records whether it was ever invoked.
private final class StubCreateCommentTransport: ClientTransport, @unchecked Sendable {
    private let responseJSON: Data
    private(set) var didSendCreateComment = false

    init(commentResponse: CommentResponse) throws {
        let encoder = JSONEncoder()
        // The generated client decodes dates via LemmyDateTranscoder, which
        // accepts the Lemmy 0.19 format: 2024-06-09T11:54:37.981990Z (UTC,
        // 6 fractional digits, trailing Z).
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        responseJSON = try encoder.encode(commentResponse)
    }

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        if operationID == "createComment" {
            didSendCreateComment = true
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(responseJSON))
        }
        throw UnexpectedOperation(operationID: operationID)
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

@MainActor
struct LemmyServiceCreateCommentTests {
    private let keychainId = "keychain-1"
    private let serverPostId: Lemmy.PostID = 1

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    /// Seeds the minimal account + site + post so that the comment mirror can
    /// resolve the account/site ids and find the post row to attach to.
    /// Returns (accountId, siteId).
    @discardableResult
    private func seedAccountSiteAndPost() async throws -> (accountId: Int64, siteId: Int64) {
        let keychainId = keychainId
        let ids = try await appDatabase.writer.write { db -> (Int64, Int64) in
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

            return (account.id!, site.id!)
        }

        let postView = Lemmy.PostView.fake(
            post: .fake(creator: .fake, community: .fake),
            creator: .fake,
            community: .fake
        )
        _ = try await appDatabase.upsertPost(
            from: postView,
            accountId: ids.0,
            siteId: ids.1
        )

        return (ids.0, ids.1)
    }

    @Test
    func createCommentUpsertsReturnedCommentIntoDatabase() async throws {
        try await seedAccountSiteAndPost()

        let newCommentId: Lemmy.CommentID = 42
        // The stub transport encodes this generated v3 CommentView to v3 JSON,
        // which the neutral createComment endpoint decodes and mirrors.
        let comment = V3.comment(id: newCommentId)
        let commentView = V3.commentView(
            comment: comment,
            creator: V3.person(),
            post: V3.post(),
            community: V3.community()
        )
        let response = CommentResponse(comment_view: commentView, recipient_ids: [])

        let transport = try StubCreateCommentTransport(commentResponse: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.createComment(
            serverPostId: serverPostId,
            content: "hello",
            parentCommentId: nil
        )

        #expect(transport.didSendCreateComment, "createComment should call the api")

        // The mirrored comment must now be queryable via its server id.
        let storedBody = try await appDatabase.writer.read { db -> String? in
            try CommentRecord
                .filter(Column("localCommentId") == Int64(newCommentId))
                .fetchOne(db)?
                .body
        }
        #expect(storedBody == comment.content)
    }

    @Test
    func createCommentOnSignedOutAccountThrowsAndSkipsApi() async throws {
        try await seedAccountSiteAndPost()

        // The transport should never be reached; encode an arbitrary response.
        let commentView = V3.commentView(
            comment: V3.comment(id: 1),
            creator: V3.person(),
            post: V3.post(),
            community: V3.community()
        )
        let response = CommentResponse(comment_view: commentView, recipient_ids: [])

        let transport = try StubCreateCommentTransport(commentResponse: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        do {
            try await service.createComment(
                serverPostId: serverPostId,
                content: "hello",
                parentCommentId: nil
            )
            Issue.record("Expected createComment to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }

        #expect(
            !transport.didSendCreateComment,
            "createComment must not hit the api when the account is signed out"
        )
    }
}
