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

struct OutboxNetworkPerformingProtocolTests {
    @Test
    func fakeRecordsAndThrows() async throws {
        let fake = FakeOutboxPerformer()
        await fake.setOutcome(.fail(LemmyServiceError.requiresAuthentication), for: .vote)
        await #expect(throws: (any Error).self) {
            try await fake.perform(.init(entityType: .post, entityServerId: 1, desiredState: .vote(.liked)))
        }
        #expect(await fake.performed.count == 1)
    }
}

// MARK: - Subscribe performer (real LemmyOutboxPerformer)

/// Decoded shape of the `followCommunity` request body, so the test can assert
/// the performer sent the right community id + follow flag.
private struct FollowCommunityRequest: Decodable {
    let community_id: Int32
    let follow: Bool
}

/// Stub `ClientTransport` returning a canned `CommunityResponse` for the
/// `followCommunity` operation. Captures the request body so the test can verify
/// the arguments the performer sent, and counts how many times it was hit.
private final class StubFollowCommunityTransport: ClientTransport, @unchecked Sendable {
    private let responseJSON: Data
    private(set) var followCalls = 0
    private(set) var lastRequest: FollowCommunityRequest?

    init(communityResponse: Lemmy.CommunityResponse) throws {
        let encoder = JSONEncoder()
        // The generated client decodes dates via LemmyDateTranscoder (Lemmy 0.19
        // format: 2024-06-09T11:54:37.981990Z).
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        responseJSON = try encoder.encode(communityResponse)
    }

    func send(
        _: HTTPRequest,
        body: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard operationID == "followCommunity" else {
            throw UnexpectedOperation(operationID: operationID)
        }
        followCalls += 1
        if let body {
            let data = try await Data(collecting: body, upTo: .max)
            lastRequest = try? JSONDecoder().decode(FollowCommunityRequest.self, from: data)
        }
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(responseJSON))
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

struct LemmyOutboxPerformerSubscribeTests {
    private func makeApi(transport: any ClientTransport) throws -> LemmyApi {
        try LemmyApi(
            instanceUrl: #require(URL(string: "https://example.com")),
            credential: LemmyCredential(jwt: "fake-jwt"),
            transport: transport
        )
    }

    @Test
    func subscribeSendsFollowTrueAndMirrorsAuthoritativeState() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(db)
        // The optimistic Pending projection is already applied locally.
        let cid = try await seedCommunity(db, accountId: accountId, subscribed: .pending)

        // The server confirms Subscribed. `CommunityResponse.community_view` is
        // the generated v3 shape, so build it via the V3 fake.
        let view = V3.communityView(subscribed: .Subscribed)
        let response = Lemmy.CommunityResponse(community_view: view, discussion_languages: [])
        let transport = try StubFollowCommunityTransport(communityResponse: response)
        let api = try makeApi(transport: transport)
        let performer = LemmyOutboxPerformer(api: api, appDatabase: db, accountId: accountId, siteId: siteId)

        try await performer.perform(
            .init(entityType: .community, entityServerId: cid, desiredState: .subscribe(true))
        )

        #expect(transport.followCalls == 1)
        #expect(transport.lastRequest?.community_id == Int32(cid))
        #expect(transport.lastRequest?.follow == true)

        // The authoritative mirror upgraded the optimistic Pending to Subscribed.
        let (state, followed) = try await readCommunitySubscribed(db, accountId: accountId, serverCommunityId: cid)
        #expect(state == "Subscribed")
        #expect(followed == true)
    }

    @Test
    func unsubscribeSendsFollowFalseAndMirrorsNotSubscribed() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(db)
        let cid = try await seedCommunity(db, accountId: accountId, subscribed: .subscribed)

        let view = V3.communityView(subscribed: .NotSubscribed)
        let response = Lemmy.CommunityResponse(community_view: view, discussion_languages: [])
        let transport = try StubFollowCommunityTransport(communityResponse: response)
        let api = try makeApi(transport: transport)
        let performer = LemmyOutboxPerformer(api: api, appDatabase: db, accountId: accountId, siteId: siteId)

        try await performer.perform(
            .init(entityType: .community, entityServerId: cid, desiredState: .subscribe(false))
        )

        #expect(transport.followCalls == 1)
        #expect(transport.lastRequest?.follow == false)
        let (state, followed) = try await readCommunitySubscribed(db, accountId: accountId, serverCommunityId: cid)
        #expect(state == "NotSubscribed")
        #expect(followed == false)
    }
}
