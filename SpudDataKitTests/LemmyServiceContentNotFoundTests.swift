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

// MARK: - Stub transport

/// Fails any operation with a `{"error":"couldnt_find_post"}` response,
/// mimicking what the real Lemmy API returns for a removed or de-federated post.
/// HTTP 400 maps to `LemmyApiError.serverError` in LemmyKit's wrapper layer
/// (see `LemmyApi+GetPost.swift` / `LemmyApi+GetComments.swift`).
private final class NotFoundTransport: ClientTransport, @unchecked Sendable {
    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let body = Data(#"{"error":"couldnt_find_post"}"#.utf8)
        var response = HTTPResponse(status: .badRequest)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(body))
    }
}

// MARK: - Test harness

/// Builds an AppDatabase-backed `LemmyService` with a seeded account and one
/// cached post, then hands back the pieces the test assertions need.
///
/// Construction mirrors `LemmyServiceFetchPersistenceTests`'s `makeService`
/// helper verbatim.
struct LemmyServiceContentNotFoundHarness {
    let service: LemmyService
    let appDatabase: AppDatabase
    /// The GRDB row id of the seeded account.
    let accountId: Int64
    /// The server post id (matches `Post.fake.id` == 1).
    let serverPostId: Components.Schemas.PostID

    private static let keychainId = "keychain-content-not-found-test"

    @MainActor
    static func make(transport: any ClientTransport) async throws -> LemmyServiceContentNotFoundHarness {
        let appDatabase = try AppDatabase.inMemory()

        // Seed account + site so `markPostUnavailable(forKeychainId:)` can resolve
        // the account row id.
        let (accountId, siteId) = try await appDatabase.writer.write { db -> (Int64, Int64) in
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

        // Seed a post row so `isUnavailable` has something to update.
        let post = Components.Schemas.Post.fake(creator: .fake, community: .fake)
        let view = Components.Schemas.PostView.fake(post: post, creator: .fake, community: .fake)
        try await appDatabase.upsertPost(from: view, accountId: accountId, siteId: siteId)
        let serverPostId = post.id

        let api = LemmyApi(
            instanceUrl: URL(string: "https://example.com")!,
            credential: LemmyCredential(jwt: "fake-jwt"),
            transport: transport
        )
        let service = LemmyService(
            accountKeychainId: keychainId,
            accountIsSignedOut: false,
            appDatabase: appDatabase,
            api: api,
            reachability: StaticReachabilityMonitor(isOnline: true)
        )

        return LemmyServiceContentNotFoundHarness(
            service: service,
            appDatabase: appDatabase,
            accountId: accountId,
            serverPostId: serverPostId
        )
    }
}

// MARK: - Tests

/// Verifies that `fetchPostInfo` and `fetchComments` mark the post unavailable
/// in the database when the server returns `couldnt_find_post`.
@MainActor
struct LemmyServiceContentNotFoundTests {
    @Test
    func getPostNotFoundMarksPostUnavailable() async throws {
        let harness = try await LemmyServiceContentNotFoundHarness.make(transport: NotFoundTransport())

        var thrown: Error?
        do {
            try await harness.service.fetchPostInfo(serverPostId: harness.serverPostId)
        } catch {
            thrown = error
        }

        // Guard: the wiring only fires if the error is actually a not-found.
        #expect(thrown.map(ContentNotFound.matchesPost) == true)
        #expect(
            try await readPostUnavailable(
                harness.appDatabase,
                accountId: harness.accountId,
                serverPostId: Int64(harness.serverPostId)
            ) == true
        )
    }

    @Test
    func getCommentsNotFoundMarksPostUnavailable() async throws {
        let harness = try await LemmyServiceContentNotFoundHarness.make(transport: NotFoundTransport())

        var thrown: Error?
        do {
            try await harness.service.fetchComments(
                serverPostId: harness.serverPostId,
                sortType: .Hot
            )
        } catch {
            thrown = error
        }

        // Guard: the wiring only fires if the error is actually a not-found.
        #expect(thrown.map(ContentNotFound.matchesPost) == true)
        #expect(
            try await readPostUnavailable(
                harness.appDatabase,
                accountId: harness.accountId,
                serverPostId: Int64(harness.serverPostId)
            ) == true
        )
    }
}
