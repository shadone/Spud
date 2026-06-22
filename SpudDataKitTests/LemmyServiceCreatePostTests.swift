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
private typealias PostView = Components.Schemas.PostView
private typealias PostResponse = Components.Schemas.PostResponse

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
final class LemmyServiceCreatePostTests: XCTestCase {
    private let keychainId = "keychain-1"
    private let serverCommunityId: Components.Schemas.CommunityID = 1
    private let newServerPostId: Components.Schemas.PostID = 99

    private var appDatabase: AppDatabase!

    override func setUpWithError() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    override func tearDown() {
        appDatabase = nil
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

    /// Builds a canned createPost response carrying a post with a distinct
    /// server id so the mirror can be unambiguously read back.
    private func makePostResponse() -> PostResponse {
        let person = Person.fake
        let community = Community.fake
        var post = Post.fake(creator: person, community: community)
        post.id = newServerPostId
        post.name = "Created from a test"
        post.ap_id = "https://example.com/post/\(newServerPostId)"
        let postView = PostView.fake(post: post, creator: person, community: community)
        return PostResponse(post_view: postView)
    }

    func testCreatePostMirrorsReturnedPostIntoDatabase() async throws {
        try await seedAccountAndSite()

        let response = makePostResponse()
        let transport = try StubCreatePostTransport(postResponse: response)
        let service = makeService(accountIsSignedOut: false, transport: transport)

        let returnedId = try await service.createPost(
            serverCommunityId: serverCommunityId,
            name: "Created from a test",
            url: nil,
            body: "hello",
            nsfw: false
        )

        XCTAssertTrue(transport.didSendCreatePost, "createPost should call the api")
        XCTAssertEqual(returnedId, newServerPostId, "createPost should return the new post id")

        // The mirrored post must now be queryable via its server id.
        let newServerPostId = newServerPostId
        let storedTitle = try await appDatabase.writer.read { db -> String? in
            try PostRecord
                .filter(Column("postId") == Int64(newServerPostId))
                .fetchOne(db)?
                .title
        }
        XCTAssertEqual(storedTitle, "Created from a test")
    }

    func testCreatePostOnSignedOutAccountThrowsAndSkipsApi() async throws {
        try await seedAccountAndSite()

        let response = makePostResponse()
        let transport = try StubCreatePostTransport(postResponse: response)
        let service = makeService(accountIsSignedOut: true, transport: transport)

        do {
            _ = try await service.createPost(
                serverCommunityId: serverCommunityId,
                name: "Created from a test",
                url: nil,
                body: "hello",
                nsfw: false
            )
            XCTFail("Expected createPost to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }

        XCTAssertFalse(
            transport.didSendCreatePost,
            "createPost must not hit the api when the account is signed out"
        )
    }
}
