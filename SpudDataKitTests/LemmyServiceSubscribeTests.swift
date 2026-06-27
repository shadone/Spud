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

private typealias Community = Components.Schemas.Community
private typealias CommunityView = Components.Schemas.CommunityView
private typealias CommunityResponse = Components.Schemas.CommunityResponse

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

@MainActor
struct LemmyServiceSubscribeTests {
    private let keychainId = "keychain-1"
    private let serverCommunityId: Components.Schemas.CommunityID = 1

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

    // MARK: Subscribe

    @Test
    func setSubscribedMirrorsSubscribedStateIntoDatabase() async throws {
        let accountId = try await seedAccountAndSite()

        // The confirmed view returned by the server carries subscribed = .Subscribed.
        let subscribedView = CommunityView.fake(community: .fake, subscribed: .Subscribed)
        let response = CommunityResponse(community_view: subscribedView, discussion_languages: [])

        let transport = try StubFollowCommunityTransport(communityResponse: response)
        let service = makeService(accountIsSignedOut: false, transport: transport)

        try await service.setSubscribed(serverCommunityId: serverCommunityId, subscribed: true)

        #expect(transport.didSendFollowCommunity, "setSubscribed should call the followCommunity api")

        let serverCommunityId = serverCommunityId
        let storedState = try await appDatabase.writer.read { db -> String? in
            try CommunityRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("communityId") == Int64(serverCommunityId))
                .fetchOne(db)?
                .subscribedState
        }
        #expect(storedState == "Subscribed")
    }

    @Test
    func subscribingAddsRowToFollowedCommunitiesJunction() async throws {
        let accountId = try await seedAccountAndSite()

        let subscribedView = CommunityView.fake(community: .fake, subscribed: .Subscribed)
        let response = CommunityResponse(community_view: subscribedView, discussion_languages: [])
        let transport = try StubFollowCommunityTransport(communityResponse: response)
        let service = makeService(accountIsSignedOut: false, transport: transport)

        try await service.setSubscribed(serverCommunityId: serverCommunityId, subscribed: true)

        let followedCount = try await appDatabase.writer.read { db -> Int in
            try AccountFollowedCommunityRecord
                .filter(Column("accountId") == accountId)
                .fetchCount(db)
        }
        #expect(followedCount == 1, "subscribing should add the community to the followed-communities junction")
    }

    @Test
    func unsubscribingRemovesRowFromFollowedCommunitiesJunction() async throws {
        let accountId = try await seedAccountAndSite()

        // First subscribe so the junction has the row.
        let subscribedView = CommunityView.fake(community: .fake, subscribed: .Subscribed)
        let subscribeTransport = try StubFollowCommunityTransport(
            communityResponse: CommunityResponse(community_view: subscribedView, discussion_languages: [])
        )
        try await makeService(accountIsSignedOut: false, transport: subscribeTransport)
            .setSubscribed(serverCommunityId: serverCommunityId, subscribed: true)

        // Then unsubscribe; the confirmed view carries .NotSubscribed.
        let unsubscribedView = CommunityView.fake(community: .fake, subscribed: .NotSubscribed)
        let unsubscribeTransport = try StubFollowCommunityTransport(
            communityResponse: CommunityResponse(community_view: unsubscribedView, discussion_languages: [])
        )
        try await makeService(accountIsSignedOut: false, transport: unsubscribeTransport)
            .setSubscribed(serverCommunityId: serverCommunityId, subscribed: false)

        let followedCount = try await appDatabase.writer.read { db -> Int in
            try AccountFollowedCommunityRecord
                .filter(Column("accountId") == accountId)
                .fetchCount(db)
        }
        #expect(followedCount == 0, "unsubscribing should remove the community from the followed-communities junction")
    }

    @Test
    func setSubscribedOnSignedOutAccountThrowsAndSkipsApi() async throws {
        try await seedAccountAndSite()

        let transport = try StubFollowCommunityTransport(communityResponse: nil)
        let service = makeService(accountIsSignedOut: true, transport: transport)

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
    }
}
