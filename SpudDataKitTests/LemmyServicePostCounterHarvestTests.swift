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

// MARK: - Type aliases

private typealias Person = Components.Schemas.Person
private typealias Community = Components.Schemas.Community
private typealias PostView = Components.Schemas.PostView
private typealias GetPostResponse = Components.Schemas.GetPostResponse

// MARK: - Stub transport

/// Stub transport returning a canned `GetPostResponse` for the `getPost` operation.
private final class StubGetPostTransport: ClientTransport, @unchecked Sendable {
    private let responseJSON: Data

    init(response: GetPostResponse) throws {
        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        responseJSON = try encoder.encode(response)
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch operationID {
        case "getPost":
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(responseJSON))
        default:
            throw UnexpectedOperation(operationID: operationID)
        }
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

// MARK: - Test class

/// Counters (comment count, score) shown in the UI live on `PostRecord` and are
/// only refreshed when the app imports a full `PostView`. This locks in the
/// invariant that a `PostView`-bearing response (here `getPost`) overwrites an
/// existing row's stale counters rather than leaving them frozen — the
/// mechanism the post-detail header relies on to recover from a stale comment
/// count (e.g. "1 comment" under three rendered comments). Lemmy's getComments
/// response carries no post counters, so a fresh getPost is the only source.
@MainActor
final class LemmyServicePostCounterHarvestTests: XCTestCase {
    private let keychainId = "keychain-1"

    private var appDatabase: AppDatabase!

    override func setUpWithError() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    override func tearDown() {
        appDatabase = nil
    }

    // MARK: - Helpers

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

    private func storedCommentCount(
        accountId: Int64,
        serverPostId: Components.Schemas.PostID
    ) async throws -> Int64? {
        try await appDatabase.writer.write { db -> Int64? in
            try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == Int64(serverPostId))
                .fetchOne(db)?
                .numberOfComments
        }
    }

    private func makeService(transport: any ClientTransport) -> LemmyService {
        let api = LemmyApi(
            instanceUrl: URL(string: "https://example.com")!,
            credential: LemmyCredential(jwt: "fake-jwt"),
            transport: transport
        )
        return LemmyService(
            accountKeychainId: keychainId,
            accountIsSignedOut: false,
            appDatabase: appDatabase,
            api: api,
            reachability: StaticReachabilityMonitor(isOnline: true)
        )
    }

    private func makePostView(commentCount: Int64) -> PostView {
        let person = Person.fake
        let community = Community.fake
        let post = Components.Schemas.Post.fake(creator: person, community: community)
        var view = PostView.fake(post: post, creator: person, community: community)
        view.counts.comments = commentCount
        return view
    }

    // MARK: - Test

    /// Importing a fresh `PostView` must overwrite an existing row's stale
    /// comment count, so the post-detail header recovers once a counter-bearing
    /// response (getPost) arrives.
    func testFetchPostInfoUpdatesStaleCommentCount() async throws {
        let ids = try await seedAccountAndSite()

        // Seed the post locally with a STALE comment count of 1.
        let stalePostView = makePostView(commentCount: 1)
        let serverPostId = stalePostView.post.id
        try await appDatabase.upsertPost(
            from: stalePostView,
            accountId: ids.accountId,
            siteId: ids.siteId
        )
        let before = try await storedCommentCount(accountId: ids.accountId, serverPostId: serverPostId)
        XCTAssertEqual(before, 1, "precondition: stored count starts stale at 1")

        // Server now reports 3 comments via getPost.
        let freshPostView = makePostView(commentCount: 3)
        let getPostResponse = GetPostResponse(
            post_view: freshPostView,
            community_view: .fake(community: Community.fake),
            moderators: [],
            cross_posts: []
        )
        let service = try makeService(transport: StubGetPostTransport(response: getPostResponse))

        try await service.fetchPostInfo(serverPostId: serverPostId)

        let after = try await storedCommentCount(accountId: ids.accountId, serverPostId: serverPostId)
        XCTAssertEqual(after, 3, "importing a fresh PostView must refresh the stored comment count")
    }
}
