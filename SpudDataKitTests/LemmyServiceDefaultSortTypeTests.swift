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

/// Stub `ClientTransport` that answers `saveUserSettings` and captures the
/// outgoing request body so a test can assert which sort was pushed.
private final class StubDefaultSortTransport: ClientTransport, @unchecked Sendable {
    private(set) var saveUserSettingsBody: [String: Any]?

    func send(
        _: HTTPRequest,
        body: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch operationID {
        case "saveUserSettings":
            if let body {
                let data = try await Data(collecting: body, upTo: .max)
                saveUserSettingsBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(Data(#"{"success":true}"#.utf8)))

        default:
            throw UnexpectedOperation(operationID: operationID)
        }
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

@MainActor
struct LemmyServiceDefaultSortTypeTests {
    private let keychainId = "keychain-default-sort-push-test"

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

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

    /// Pushing a Top-Week default must preserve the time window: on v3 the
    /// outgoing `saveUserSettings` carries `default_sort_type: "TopWeek"`, not the
    /// window-less `TopAll` it used to collapse to.
    @Test
    func setDefaultSortType_topWeek_pushesTopWeekPreservingWindow() async throws {
        try await seedAccountAndSite()

        let transport = StubDefaultSortTransport()
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.setDefaultSortType(.TopWeek)

        let body = try #require(transport.saveUserSettingsBody)
        #expect(body["default_sort_type"] as? String == "TopWeek")
    }
}
