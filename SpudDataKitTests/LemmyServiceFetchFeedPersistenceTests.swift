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
/// page so the test can exercise persistence failure paths without hitting the
/// network.
private final class StubGetPostsTransport: ClientTransport, @unchecked Sendable {
    private let getPostsResponseJSON: Data

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

@MainActor
final class LemmyServiceFetchFeedPersistenceTests: XCTestCase {
    private let keychainId = "keychain-persistence-1"

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
            api: api,
            reachability: StaticReachabilityMonitor(isOnline: true)
        )
    }

    /// When no account/site row has been seeded, `fetchFeed` must throw rather
    /// than silently succeeding and leaving the feed row uncreated. This
    /// exercises the nil-return path of `accountSiteIds()` inside
    /// `mirrorFeedPageToAppDatabase`.
    func testFetchFeedThrowsWhenAccountRowMissing() async throws {
        // Intentionally do NOT seed an account/site row.

        let transport = try StubGetPostsTransport(response: GetPostsResponse(posts: []))
        let service = makeService(accountIsSignedOut: false, transport: transport)

        let feed = FeedHandle(
            feedKey: UUID().uuidString,
            feedType: .frontpage(listingType: .All, sortType: .Active)
        )

        do {
            _ = try await service.fetchFeed(feed, pageCursor: nil)
            XCTFail("Expected fetchFeed to throw when no account/site row exists")
        } catch {
            // Any thrown error is acceptable — what matters is that it did not
            // silently succeed.
        }

        // The feed row must NOT have been created.
        let feedRowId = appDatabase.feedRowIdSync(forFeedKey: feed.feedKey)
        XCTAssertNil(feedRowId, "No feed row should be created when account/site row is missing")
    }

    /// Regression guard: when the account and site rows are present, `fetchFeed`
    /// must succeed and produce a feed row (even for an empty page).
    func testFetchFeedSucceedsAndCreatesFeedRowWhenSeeded() async throws {
        try await seedAccountAndSite()

        let transport = try StubGetPostsTransport(response: GetPostsResponse(posts: []))
        let service = makeService(accountIsSignedOut: false, transport: transport)

        let feed = FeedHandle(
            feedKey: UUID().uuidString,
            feedType: .frontpage(listingType: .All, sortType: .Active)
        )

        // Must not throw.
        _ = try await service.fetchFeed(feed, pageCursor: nil)

        // The feed row must have been created (appendFeedPage upserts even for
        // an empty page).
        let feedRowId = appDatabase.feedRowIdSync(forFeedKey: feed.feedKey)
        XCTAssertNotNil(feedRowId, "A feed row should be created after a successful fetchFeed")
    }
}
