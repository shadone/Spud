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
private typealias CommentView = Components.Schemas.CommentView
private typealias CommentResponse = Components.Schemas.CommentResponse

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
final class LemmyServiceCreateCommentTests: XCTestCase {
    private let keychainId = "keychain-1"
    private let serverPostId: Components.Schemas.PostID = 1

    private var appDatabase: AppDatabase!

    override func setUpWithError() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    override func tearDown() {
        appDatabase = nil
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

        let postView = Components.Schemas.PostView.fake(
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
            api: api,
            reachability: StaticReachabilityMonitor(isOnline: true)
        )
    }

    func testCreateCommentUpsertsReturnedCommentIntoDatabase() async throws {
        try await seedAccountSiteAndPost()

        let newCommentId: Components.Schemas.CommentID = 42
        let person = Person.fake
        let community = Community.fake
        let post = Post.fake(creator: person, community: community)
        let comment = Comment.fake(
            id: newCommentId,
            post: post,
            creator: person,
            parent: .root
        )
        let commentView = CommentView.fake(
            comment: comment,
            creator: person,
            post: post,
            community: community,
            childCount: 0
        )
        let response = CommentResponse(comment_view: commentView, recipient_ids: [])

        let transport = try StubCreateCommentTransport(commentResponse: response)
        let service = makeService(accountIsSignedOut: false, transport: transport)

        try await service.createComment(
            serverPostId: serverPostId,
            content: "hello",
            parentCommentId: nil
        )

        XCTAssertTrue(transport.didSendCreateComment, "createComment should call the api")

        // The mirrored comment must now be queryable via its server id.
        let storedBody = try await appDatabase.writer.read { db -> String? in
            try CommentRecord
                .filter(Column("localCommentId") == Int64(newCommentId))
                .fetchOne(db)?
                .body
        }
        XCTAssertEqual(storedBody, comment.content)
    }

    func testCreateCommentOnSignedOutAccountThrowsAndSkipsApi() async throws {
        try await seedAccountSiteAndPost()

        // The transport should never be reached; encode an arbitrary response.
        let person = Person.fake
        let community = Community.fake
        let post = Post.fake(creator: person, community: community)
        let commentView = CommentView.fake(
            comment: .fake(id: 1, post: post, creator: person, parent: .root),
            creator: person,
            post: post,
            community: community,
            childCount: 0
        )
        let response = CommentResponse(comment_view: commentView, recipient_ids: [])

        let transport = try StubCreateCommentTransport(commentResponse: response)
        let service = makeService(accountIsSignedOut: true, transport: transport)

        do {
            try await service.createComment(
                serverPostId: serverPostId,
                content: "hello",
                parentCommentId: nil
            )
            XCTFail("Expected createComment to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }

        XCTAssertFalse(
            transport.didSendCreateComment,
            "createComment must not hit the api when the account is signed out"
        )
    }
}
