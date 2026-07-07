//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import HTTPTypes
import LemmyKit
import OpenAPIRuntime
import Testing
@testable import SpudDataKit

/// Stub transport whose `likePost` always fails with a network error, so the
/// outbox drain classifies it as transient and the optimistic write stands
/// rather than being reconciled away by an authoritative response. This lets
/// the test assert the *optimistic* projection produced by delegating
/// `LemmyService.vote(...)` into the outbox.
private final class FailingLikeTransport: ClientTransport, @unchecked Sendable {
    private(set) var didSendLikePost = false

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch operationID {
        case "likePost":
            didSendLikePost = true
            throw URLError(.timedOut)
        default:
            throw URLError(.unsupportedURL)
        }
    }
}

@MainActor
struct LemmyServiceOutboxDelegationTests {
    /// Delegating `vote(serverPostId:)` into the outbox applies the optimistic
    /// projection synchronously: with a starting score of 5 and no vote, an
    /// upvote becomes voteStatus 1 / score 6 even though the network call fails
    /// (the failure is transient, so the optimistic write is retained for retry).
    @Test
    func votePostDelegatesOptimisticWriteThroughOutbox() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let serverPostId = try await seedPost(
            appDatabase,
            accountId: accountId,
            siteId: siteId,
            score: 5,
            voteStatus: nil
        )

        let transport = FailingLikeTransport()
        let api = try LemmyApi(
            instanceUrl: #require(URL(string: "https://example.com")),
            credential: LemmyCredential(jwt: "fake-jwt"),
            transport: transport
        )
        let service = LemmyService(
            accountKeychainId: "keychain-outbox-test",
            accountIsSignedOut: false,
            appDatabase: appDatabase,
            api: api,
            reachability: StaticReachabilityMonitor(isOnline: true)
        )

        try await service.vote(serverPostId: Lemmy.PostID(serverPostId), vote: .upvote)

        // Delegation reached the network performer...
        #expect(transport.didSendLikePost)

        // ...and the optimistic write is visible in the DB.
        let (score, vote) = try await readPostVote(
            appDatabase,
            accountId: accountId,
            serverPostId: serverPostId
        )
        #expect(vote == 1)
        #expect(score == 6)
    }
}
