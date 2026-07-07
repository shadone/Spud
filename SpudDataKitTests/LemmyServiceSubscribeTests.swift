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

private typealias Community = Lemmy.Community
private typealias CommunityView = Lemmy.CommunityView
private typealias CommunityResponse = Lemmy.CommunityResponse

/// Stub `ClientTransport` that returns canned JSON for the `followCommunity`
/// operation and records whether it was invoked.
private final class StubFollowCommunityTransport: ClientTransport, @unchecked Sendable {
    private let responseJSON: Data?
    private(set) var didSendFollowCommunity = false

    init(communityResponse: CommunityResponse? = nil) throws {
        let encoder = JSONEncoder()
        // Matches LemmyDateTranscoder's expected Lemmy 0.19 date format.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        responseJSON = try communityResponse.map { try encoder.encode($0) }
    }

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch operationID {
        case "followCommunity":
            didSendFollowCommunity = true
            guard let responseJSON else { throw UnexpectedOperation(operationID: operationID) }
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

/// Stub transport whose `followCommunity` always fails with a network error,
/// so the outbox drain classifies it as transient and the optimistic write
/// stands rather than being reconciled away by an authoritative response. This
/// lets tests assert the *optimistic* projection produced by delegating
/// `LemmyService.setSubscribed` into the outbox — mirrors
/// `LemmyServiceOutboxDelegationTests.FailingLikeTransport`.
private final class FailingFollowCommunityTransport: ClientTransport, @unchecked Sendable {
    private(set) var didSendFollowCommunity = false

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch operationID {
        case "followCommunity":
            didSendFollowCommunity = true
            throw URLError(.timedOut)
        default:
            throw URLError(.unsupportedURL)
        }
    }
}

/// `LemmyService.setSubscribed` delegates into the durable mutation outbox
/// (see `OutboxService` / `spud-optimistic-mutation-outbox`), exactly like
/// vote/save/hide/delete. The community's `subscribedState` + the
/// `accountFollowedCommunity` junction flip **synchronously** inside
/// `enqueue`, before any network round trip completes, and the outbox's own
/// authoritative post-send mirror later reconciles them to the server's
/// actual answer. These tests pin that contract; they would FAIL against the
/// old confirm-then-mirror implementation (verified RED before Task 3's
/// `LemmyService` change landed).
@MainActor
struct LemmyServiceSubscribeTests {
    private let keychainId = "keychain-1"
    private let serverCommunityId: Lemmy.CommunityID = 1

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    /// Seeds account + site and returns the account row id.
    @discardableResult
    private func seedAccountAndSite() async throws -> Int64 {
        let keychainId = keychainId
        return try await appDatabase.writer.write { db -> Int64 in
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

            return account.id!
        }
    }

    // MARK: Subscribe — optimistic guarantee

    /// (a) A subscribe delegates into the outbox: the Pending state + the
    /// followed-communities junction row apply synchronously inside
    /// `enqueue`, even though the network call fails (a timeout is
    /// transient, so the drain leaves the optimistic write in place for
    /// later retry rather than rolling it back).
    @Test
    func setSubscribedAppliesOptimisticPendingSynchronouslyEvenWhenNetworkFails() async throws {
        let accountId = try await seedAccountAndSite()
        try await seedCommunity(
            appDatabase,
            accountId: accountId,
            serverCommunityId: Int64(serverCommunityId),
            subscribed: .notSubscribed
        )

        let transport = FailingFollowCommunityTransport()
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.setSubscribed(serverCommunityId: serverCommunityId, subscribed: true)

        // Delegation reached the network performer...
        #expect(transport.didSendFollowCommunity, "setSubscribed should call the followCommunity api")

        // ...and the optimistic write is visible in the DB despite the failure.
        let (state, followed) = try await readCommunitySubscribed(
            appDatabase,
            accountId: accountId,
            serverCommunityId: Int64(serverCommunityId)
        )
        #expect(state == "Pending")
        #expect(followed == true)
    }

    /// (b) After a successful drain, the server's authoritative response
    /// replaces the optimistic Pending with its actual confirmed state (here
    /// Subscribed), keeping the junction consistent with it.
    @Test
    func setSubscribedReplacesPendingWithAuthoritativeStateAfterSuccessfulDrain() async throws {
        let accountId = try await seedAccountAndSite()
        try await seedCommunity(
            appDatabase,
            accountId: accountId,
            serverCommunityId: Int64(serverCommunityId),
            subscribed: .notSubscribed
        )

        let subscribedView = CommunityView.fake(community: .fake, subscribed: .Subscribed)
        let response = CommunityResponse(community_view: subscribedView, discussion_languages: [])
        let transport = try StubFollowCommunityTransport(communityResponse: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.setSubscribed(serverCommunityId: serverCommunityId, subscribed: true)

        #expect(transport.didSendFollowCommunity, "setSubscribed should call the followCommunity api")

        let (state, followed) = try await readCommunitySubscribed(
            appDatabase,
            accountId: accountId,
            serverCommunityId: Int64(serverCommunityId)
        )
        #expect(state == "Subscribed")
        #expect(followed == true)
    }

    /// (c) An unsubscribe applies its optimistic projection synchronously too
    /// — the junction row is removed and the state flips to NotSubscribed —
    /// even when the network call fails.
    @Test
    func setSubscribedFalseRemovesJunctionAndSetsNotSubscribedOptimistically() async throws {
        let accountId = try await seedAccountAndSite()
        try await seedCommunity(
            appDatabase,
            accountId: accountId,
            serverCommunityId: Int64(serverCommunityId),
            subscribed: .subscribed
        )

        let transport = FailingFollowCommunityTransport()
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.setSubscribed(serverCommunityId: serverCommunityId, subscribed: false)

        #expect(transport.didSendFollowCommunity, "setSubscribed should call the followCommunity api")

        let (state, followed) = try await readCommunitySubscribed(
            appDatabase,
            accountId: accountId,
            serverCommunityId: Int64(serverCommunityId)
        )
        #expect(state == "NotSubscribed")
        #expect(followed == false)
    }

    // MARK: Signed out

    /// (d) A signed-out account still throws before reaching the api, and
    /// writes nothing to the database — the auth guard runs before enqueue.
    @Test
    func setSubscribedOnSignedOutAccountThrowsAndSkipsApi() async throws {
        let accountId = try await seedAccountAndSite()
        try await seedCommunity(
            appDatabase,
            accountId: accountId,
            serverCommunityId: Int64(serverCommunityId),
            subscribed: .notSubscribed
        )

        let transport = try StubFollowCommunityTransport(communityResponse: nil)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        do {
            try await service.setSubscribed(serverCommunityId: serverCommunityId, subscribed: true)
            Issue.record("Expected setSubscribed to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }

        #expect(
            !(transport.didSendFollowCommunity),
            "setSubscribed must not hit the api when the account is signed out"
        )

        let (state, followed) = try await readCommunitySubscribed(
            appDatabase,
            accountId: accountId,
            serverCommunityId: Int64(serverCommunityId)
        )
        #expect(state == "NotSubscribed", "signed-out setSubscribed must not write to the database")
        #expect(followed == false)
    }
}
