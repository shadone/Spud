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

/// Stub `ClientTransport` that answers the `saveUserSettings` operation and
/// records whether it was invoked.
private final class StubBlurNsfwTransport: ClientTransport, @unchecked Sendable {
    private(set) var didSendSaveUserSettings = false

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch operationID {
        case "saveUserSettings":
            didSendSaveUserSettings = true
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
struct LemmyServiceBlurNsfwTests {
    private let keychainId = "keychain-blur-nsfw-service-test"

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

    // MARK: Signed in

    @Test
    func setBlurNsfw_signedIn_callsSaveUserSettings() async throws {
        try await seedAccountAndSite()

        let transport = StubBlurNsfwTransport()
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.setBlurNsfw(false)

        #expect(
            transport.didSendSaveUserSettings,
            "setBlurNsfw should call the saveUserSettings api when signed in"
        )
    }

    @Test
    func setBlurNsfw_signedIn_mirrorsValueIntoDatabase() async throws {
        try await seedAccountAndSite()

        let transport = StubBlurNsfwTransport()
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.setBlurNsfw(false)

        let keychainId = keychainId
        let account = try await appDatabase.writer.read { db in
            try AccountRecord.filter(Column("accountKeychainId") == keychainId).fetchOne(db)
        }
        #expect(account?.blurNsfw == false)
    }

    // MARK: Signed out

    @Test
    func setBlurNsfw_signedOut_isNoOp() async throws {
        let transport = StubBlurNsfwTransport()
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        try await service.setBlurNsfw(false)

        #expect(
            !transport.didSendSaveUserSettings,
            "setBlurNsfw must not call the api when the account is signed out"
        )
    }
}
