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

// MARK: - Type aliases

private typealias GetPostResponse = Lemmy.GetPostResponse

// MARK: - Stub transport

/// Stub transport returning a canned `GetPostResponse` for the `getPost`
/// operation. Copy of the private stub in `LemmyServicePostCounterHarvestTests`
/// (test-target duplication is the existing convention here — see e.g.
/// `seedAccountAndSite` repeated per-file across this directory).
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

// MARK: - Test struct

/// `fetchPostInfo` harvests `PostDetail.crossPosts` twice: once for counter
/// freshness (`LemmyServicePostCounterHarvestTests`) and once for the
/// *relationship*, persisted to the `postCrossPost` junction so the post-detail
/// screen can render "Cross-posted to N communities". This covers the latter,
/// end to end through the real stub-transport `fetchPostInfo` call (not just the
/// junction write/read in isolation - see `CrossPostTests` for that).
@MainActor
struct LemmyServiceCrossPostJunctionTests {
    private let keychainId = "keychain-1"

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

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

    /// Generated v3 builder for the `getPost` response payload. Builds the post
    /// and its community explicitly (rather than `V3.postView(postId:communityId:)`,
    /// whose community convenience always names it "world") so each cross-post
    /// lands in a distinctly-named community and the junction's community join
    /// is exercised.
    private func responsePostView(
        postId: Lemmy.PostID,
        communityId: Lemmy.CommunityID,
        communityName: String
    ) -> Components.Schemas.PostView {
        V3.postView(
            post: V3.post(id: postId, communityId: communityId),
            creator: V3.person(),
            community: V3.community(id: communityId, name: communityName)
        )
    }

    // MARK: - Tests

    @Test
    func fetchPostInfoPersistsCrossPostJunctionInServerOrder() async throws {
        _ = try await seedAccountAndSite()

        let mainView = responsePostView(postId: 1, communityId: 1, communityName: "opened")
        let crossA = responsePostView(postId: 2, communityId: 2, communityName: "alpha")
        let crossB = responsePostView(postId: 3, communityId: 3, communityName: "beta")
        let getPostResponse = GetPostResponse(
            post_view: mainView,
            community_view: V3.communityView(community: V3.community(id: 1, name: "opened")),
            moderators: [],
            // Server order: B before A. The junction must preserve this, not
            // re-sort by id.
            cross_posts: [crossB, crossA]
        )
        let service = try LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            transport: StubGetPostTransport(response: getPostResponse)
        )

        try await service.fetchPostInfo(serverPostId: mainView.post.id)

        let summaries = appDatabase.crossPostSummariesSync(
            forKeychainId: keychainId,
            serverPostId: Int64(mainView.post.id)
        )
        #expect(summaries.map(\.serverPostId) == [Int64(crossB.post.id), Int64(crossA.post.id)])
        #expect(summaries.map(\.communityName) == ["beta", "alpha"])
    }

    @Test
    func fetchPostInfoWithNoCrossPostsClearsAnyExistingJunction() async throws {
        _ = try await seedAccountAndSite()

        let mainView = responsePostView(postId: 1, communityId: 1, communityName: "opened")
        let crossA = responsePostView(postId: 2, communityId: 2, communityName: "alpha")

        // First fetch reports one cross-post.
        let firstResponse = GetPostResponse(
            post_view: mainView,
            community_view: V3.communityView(community: V3.community(id: 1)),
            moderators: [],
            cross_posts: [crossA]
        )
        let firstService = try LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            transport: StubGetPostTransport(response: firstResponse)
        )
        try await firstService.fetchPostInfo(serverPostId: mainView.post.id)
        #expect(!appDatabase.crossPostSummariesSync(
            forKeychainId: keychainId,
            serverPostId: Int64(mainView.post.id)
        ).isEmpty)

        // A later fetch reports none (the other side unlinked, or was itself
        // deleted) - the junction must clear, not keep serving the stale set.
        let secondResponse = GetPostResponse(
            post_view: mainView,
            community_view: V3.communityView(community: V3.community(id: 1)),
            moderators: [],
            cross_posts: []
        )
        let secondService = try LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            transport: StubGetPostTransport(response: secondResponse)
        )
        try await secondService.fetchPostInfo(serverPostId: mainView.post.id)

        #expect(appDatabase.crossPostSummariesSync(
            forKeychainId: keychainId,
            serverPostId: Int64(mainView.post.id)
        ).isEmpty)
    }
}
