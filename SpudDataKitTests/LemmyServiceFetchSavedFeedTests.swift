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

private typealias GetPostsResponse = Lemmy.GetPostsResponse

/// Stub `ClientTransport` that answers the `getPosts` operation with a canned
/// response and records the query string it was asked to send, so the test can
/// assert the `.saved` FeedType maps to `saved_only=true`.
private final class StubGetPostsTransport: ClientTransport, @unchecked Sendable {
    private let getPostsResponseJSON: Data
    private(set) var didSendGetPosts = false
    private(set) var lastQuery: String?

    init(response: GetPostsResponse) throws {
        // v3 wire dates are ISO-8601-with-microseconds strings, not the
        // default JSONEncoder numeric epoch — required once a fixture
        // carries an actual post (its `published` date), not just an empty
        // `posts` array.
        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
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

@MainActor
struct LemmyServiceFetchSavedFeedTests {
    private let keychainId = "keychain-1"

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    /// Seeds an account + site so `fetchFeed`'s `appendFeedPage` mirror can
    /// resolve the account/site ids before importing the server response.
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

    /// Regression guard for the Phase 6 neutral migration: `LemmyService.fetchFeed`'s
    /// `.saved` case now calls `LemmyApi.getSavedPostsNeutral(pageCursor:)`, whose v3
    /// path reuses `getPosts` with `saved_only=true` (see
    /// `LemmyApi+AccountFeedsNeutral.swift`). This exercises the full round trip
    /// through `LemmyService` — the stub transport is hit with the `saved_only`
    /// filter, and the returned posts land in the local database — rather than
    /// pinning the former (broken) empty-page behavior.
    @Test
    func fetchSavedFeedFetchesFromApiAndImportsPosts() async throws {
        try await seedAccountAndSite()

        let savedPostId: Lemmy.PostID = 42
        let response = GetPostsResponse(
            posts: [V3.postView(postId: savedPostId)],
            next_page: "Pc7"
        )
        let transport = try StubGetPostsTransport(response: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        let feed = FeedHandle(
            feedKey: UUID().uuidString,
            feedType: .saved(sortType: .New)
        )

        let nextCursor = try await service.fetchFeed(feed, pageCursor: nil, showNsfw: false)

        #expect(transport.didSendGetPosts, "the saved feed must hit getPosts via getSavedPostsNeutral's v3 path")
        let query = try #require(transport.lastQuery)
        #expect(query.contains("saved_only=true"), "the saved feed must request saved_only=true, got query: \(query)")
        #expect(nextCursor == "Pc7", "the wire next_page cursor must bridge through to the returned page cursor")

        let postRowId = appDatabase.postRowIdSync(forKeychainId: keychainId, serverPostId: Int64(savedPostId))
        #expect(postRowId != nil, "the saved post returned by getSavedPostsNeutral must be imported into the local database")
    }

    /// The `.saved` feed threads its selected sort onto the v3 `getPosts` wire
    /// query via `getSavedPostsNeutral(sort:timeRange:)`. `.TopWeek` un-fuses to
    /// `(.top, .week)` and re-fuses on the v3 backend to `sort=TopWeek`, so both
    /// the sort and its time window reach the request. (v4's `ListPersonSaved`
    /// has no sort param — documented no-op there.)
    @Test
    func fetchSavedFeedThreadsSortIntoGetPostsQuery() async throws {
        try await seedAccountAndSite()

        let transport = try StubGetPostsTransport(response: GetPostsResponse(posts: []))
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        let feed = FeedHandle(
            feedKey: UUID().uuidString,
            feedType: .saved(sortType: .TopWeek)
        )

        _ = try await service.fetchFeed(feed, pageCursor: nil, showNsfw: false)

        let query = try #require(transport.lastQuery)
        #expect(
            query.contains("sort=TopWeek"),
            "the saved feed must forward its selected sort (TopWeek) to getPosts, got query: \(query)"
        )
    }

    /// `fetchFeed`'s frontpage case threads `showNsfw` onto the `getPosts` wire
    /// query via `getPostsNeutral(showNsfw:)`, so v3 filters NSFW server-side
    /// (matching v4, which filters by the account setting). The client's synced
    /// show-NSFW preference reaches the request param either way.
    @Test
    func fetchFeedThreadsShowNsfwIntoGetPostsQuery() async throws {
        try await seedAccountAndSite()

        let feed = FeedHandle(
            feedKey: UUID().uuidString,
            feedType: .frontpage(listingType: .All, sortType: .Hot)
        )

        // Hidden by default: show_nsfw=false on the wire.
        let hideTransport = try StubGetPostsTransport(response: GetPostsResponse(posts: []))
        let hideService = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: hideTransport
        )
        _ = try await hideService.fetchFeed(feed, pageCursor: nil, showNsfw: false)
        let hideQuery = try #require(hideTransport.lastQuery)
        #expect(
            hideQuery.contains("show_nsfw=false"),
            "fetchFeed(showNsfw: false) must request show_nsfw=false, got query: \(hideQuery)"
        )

        // Shown when enabled: show_nsfw=true on the wire.
        let showTransport = try StubGetPostsTransport(response: GetPostsResponse(posts: []))
        let showService = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: showTransport
        )
        _ = try await showService.fetchFeed(feed, pageCursor: nil, showNsfw: true)
        let showQuery = try #require(showTransport.lastQuery)
        #expect(
            showQuery.contains("show_nsfw=true"),
            "fetchFeed(showNsfw: true) must request show_nsfw=true, got query: \(showQuery)"
        )
    }

    @Test
    func fetchSavedFeedOnSignedOutAccountThrowsAndSkipsApi() async throws {
        try await seedAccountAndSite()

        let transport = try StubGetPostsTransport(response: GetPostsResponse(posts: []))
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        let feed = FeedHandle(
            feedKey: UUID().uuidString,
            feedType: .saved(sortType: .New)
        )

        do {
            _ = try await service.fetchFeed(feed, pageCursor: nil, showNsfw: false)
            Issue.record("Expected fetchFeed(.saved) to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }

        #expect(
            !(transport.didSendGetPosts),
            "fetchFeed(.saved) must not hit the api when the account is signed out"
        )
    }
}
