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

private typealias PostResponse = Lemmy.PostResponse

/// Stub `ClientTransport` that returns a canned JSON response for the
/// `createPost` operation and records whether it was ever invoked.
private final class StubCreatePostTransport: ClientTransport, @unchecked Sendable {
    private let responseJSON: Data
    private(set) var didSendCreatePost = false

    init(postResponse: PostResponse) throws {
        let encoder = JSONEncoder()
        // The generated client decodes dates via LemmyDateTranscoder, which
        // accepts the Lemmy 0.19 format: 2024-06-09T11:54:37.981990Z (UTC,
        // 6 fractional digits, trailing Z).
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        responseJSON = try encoder.encode(postResponse)
    }

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        if operationID == "createPost" {
            didSendCreatePost = true
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
struct LemmyServiceCreatePostTests {
    private let keychainId = "keychain-1"
    private let serverCommunityId: Lemmy.CommunityID = 1
    private let newServerPostId: Lemmy.PostID = 99

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    /// Seeds the minimal account + site so that the post mirror can resolve the
    /// account/site ids. Returns (accountId, siteId).
    @discardableResult
    private func seedAccountAndSite() async throws -> (accountId: Int64, siteId: Int64) {
        let keychainId = keychainId
        return try await appDatabase.writer.write { db -> (Int64, Int64) in
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
    }

    /// Builds a canned createPost response carrying a post with a distinct
    /// server id so the mirror can be unambiguously read back.
    private func makePostResponse() -> PostResponse {
        // Generated v3 shapes: the stub transport encodes this to v3 JSON for
        // the neutral createPost endpoint to decode and mirror. Mutable `var`
        // fields let us stamp a distinct server id for an unambiguous read-back.
        var post = V3.post()
        post.id = newServerPostId
        post.name = "Created from a test"
        post.ap_id = "https://example.com/post/\(newServerPostId)"
        let postView = V3.postView(post: post, creator: V3.person(), community: V3.community())
        return PostResponse(post_view: postView)
    }

    @Test
    func createPostMirrorsReturnedPostIntoDatabase() async throws {
        try await seedAccountAndSite()

        let response = makePostResponse()
        let transport = try StubCreatePostTransport(postResponse: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        let returnedId = try await service.createPost(
            serverCommunityId: serverCommunityId,
            name: "Created from a test",
            url: nil,
            body: "hello",
            nsfw: false
        )

        #expect(transport.didSendCreatePost, "createPost should call the api")
        #expect(returnedId == newServerPostId, "createPost should return the new post id")

        // The mirrored post must now be queryable via its server id.
        let newServerPostId = newServerPostId
        let storedTitle = try await appDatabase.writer.read { db -> String? in
            try PostRecord
                .filter(Column("postId") == Int64(newServerPostId))
                .fetchOne(db)?
                .title
        }
        #expect(storedTitle == "Created from a test")
    }

    @Test
    func createPostOnSignedOutAccountThrowsAndSkipsApi() async throws {
        try await seedAccountAndSite()

        let response = makePostResponse()
        let transport = try StubCreatePostTransport(postResponse: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        do {
            _ = try await service.createPost(
                serverCommunityId: serverCommunityId,
                name: "Created from a test",
                url: nil,
                body: "hello",
                nsfw: false
            )
            Issue.record("Expected createPost to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }

        #expect(
            !transport.didSendCreatePost,
            "createPost must not hit the api when the account is signed out"
        )
    }
}
