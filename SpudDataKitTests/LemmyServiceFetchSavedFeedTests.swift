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

private typealias GetPostsResponse = Components.Schemas.GetPostsResponse

/// Stub `ClientTransport` that answers the `getPosts` operation with an empty
/// page and records the query string it was asked to send, so the test can
/// assert the `.saved` FeedType maps to `saved_only=true`.
private final class StubGetPostsTransport: ClientTransport, @unchecked Sendable {
    private let getPostsResponseJSON: Data
    private(set) var didSendGetPosts = false
    private(set) var lastQuery: String?

    init(response: GetPostsResponse) throws {
        let encoder = JSONEncoder()
        getPostsResponseJSON = try encoder.encode(response)
    }

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch operationID {
        case "getPosts":
            didSendGetPosts = true
            // The query string is the part after `?` in the request path.
            lastQuery = request.path.flatMap { path in
                path.split(separator: "?", maxSplits: 1).dropFirst().first.map(String.init)
            }
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(getPostsResponseJSON))

        default:
            throw UnexpectedOperation(operationID: operationID)
        }
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

final class LemmyServiceFetchSavedFeedTests: XCTestCase {
    private let keychainId = "keychain-1"

    private var appDatabase: AppDatabase!

    override func setUpWithError() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    override func tearDown() {
        appDatabase = nil
    }

    /// Seeds an account + site so `fetchFeed`'s `appendFeedPage` mirror can
    /// resolve the account/site ids after the (empty) server response.
    private func seedAccountAndSite() async throws {
        let keychainId = keychainId
        try await appDatabase.writer.write { db in
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

    func testFetchSavedFeedRequestsSavedOnlyFilter() async throws {
        try await seedAccountAndSite()

        let transport = try StubGetPostsTransport(response: GetPostsResponse(posts: []))
        let service = makeService(accountIsSignedOut: false, transport: transport)

        let feed = FeedHandle(
            feedKey: UUID().uuidString,
            feedType: .saved(sortType: .New)
        )

        _ = try await service.fetchFeed(feed, pageCursor: nil)

        XCTAssertTrue(transport.didSendGetPosts, "fetchFeed(.saved) should call the getPosts api")
        let query = try XCTUnwrap(transport.lastQuery)
        XCTAssertTrue(
            query.contains("saved_only=true"),
            "fetchFeed(.saved) must request the saved_only filter, got query: \(query)"
        )
    }

    func testFetchSavedFeedOnSignedOutAccountThrowsAndSkipsApi() async throws {
        try await seedAccountAndSite()

        let transport = try StubGetPostsTransport(response: GetPostsResponse(posts: []))
        let service = makeService(accountIsSignedOut: true, transport: transport)

        let feed = FeedHandle(
            feedKey: UUID().uuidString,
            feedType: .saved(sortType: .New)
        )

        do {
            _ = try await service.fetchFeed(feed, pageCursor: nil)
            XCTFail("Expected fetchFeed(.saved) to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }

        XCTAssertFalse(
            transport.didSendGetPosts,
            "fetchFeed(.saved) must not hit the api when the account is signed out"
        )
    }
}
