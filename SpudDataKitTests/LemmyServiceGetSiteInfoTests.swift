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

/// Stub `ClientTransport` that answers `getSite` with a canned `GetSiteResponse`
/// and counts how many times it was invoked. `getSiteInfo` should make exactly
/// one `getSite` round-trip on a v3 backend — previously it made two (a separate
/// `getSiteNeutral` then `getMyUserNeutral`, which re-fetches `getSite`).
private final class CountingGetSiteTransport: ClientTransport, @unchecked Sendable {
    private let getSiteJSON: Data
    private(set) var getSiteCallCount = 0

    init(getSite: Lemmy.GetSiteResponse) throws {
        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        getSiteJSON = try encoder.encode(getSite)
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch operationID {
        case "getSite":
            getSiteCallCount += 1
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(getSiteJSON))

        default:
            throw UnexpectedOperation(operationID: operationID)
        }
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

@MainActor
struct LemmyServiceGetSiteInfoTests {
    private let keychainId = "keychain-get-site-info-test"

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    /// A signed-in refresh makes exactly ONE `getSite` round-trip on v3 (the
    /// combined `getSiteAndMyUserNeutral` decodes both the site and `my_user`
    /// from a single response), not the two it used to make.
    @Test
    func getSiteInfo_signedIn_makesSingleGetSiteRoundTrip() async throws {
        let transport = try CountingGetSiteTransport(getSite: .fake(myUser: true))
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        _ = try await service.getSiteInfo()

        #expect(
            transport.getSiteCallCount == 1,
            "signed-in getSiteInfo should make a single getSite call, got \(transport.getSiteCallCount)"
        )
    }

    /// A signed-out fetch loads the site with a single `getSite` and tolerates
    /// the absent `my_user` (it must, since signed-out sites load). On v3 the
    /// response simply carries no `my_user`.
    @Test
    func getSiteInfo_signedOut_loadsSiteWithNilMyUser() async throws {
        let transport = try CountingGetSiteTransport(getSite: .fake(myUser: false))
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        // Must not throw despite the nil my_user.
        _ = try await service.getSiteInfo()

        #expect(
            transport.getSiteCallCount == 1,
            "signed-out getSiteInfo should make a single getSite call, got \(transport.getSiteCallCount)"
        )
    }
}
