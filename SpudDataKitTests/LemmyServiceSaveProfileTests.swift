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

/// Stub `ClientTransport` that answers the `saveUserSettings` and `getSite`
/// operations `saveProfile` issues, capturing the `saveUserSettings` request body
/// so the test can assert which fields were pushed. Mirrors the moderation /
/// blur-NSFW stubs.
private final class StubSaveProfileTransport: ClientTransport, @unchecked Sendable {
    private let getSiteJSON: Data?

    private(set) var didSendSaveUserSettings = false
    private(set) var didSendGetSite = false
    /// The decoded JSON object of the most recent `saveUserSettings` request body.
    private(set) var saveUserSettingsBody: [String: Any]?

    init(getSite: Components.Schemas.GetSiteResponse? = nil) throws {
        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        getSiteJSON = try getSite.map { try encoder.encode($0) }
    }

    func send(
        _: HTTPRequest,
        body: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch operationID {
        case "saveUserSettings":
            didSendSaveUserSettings = true
            if let body {
                let data = try await Data(collecting: body, upTo: .max)
                saveUserSettingsBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(Data(#"{"success":true}"#.utf8)))

        case "getSite":
            didSendGetSite = true
            guard let getSiteJSON else { throw UnexpectedOperation(operationID: operationID) }
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
struct LemmyServiceSaveProfileTests {
    private let keychainId = "keychain-save-profile-test"

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

    // MARK: Signed in

    @Test
    func saveProfile_signedIn_dispatchesSaveUserSettingsThenRefreshes() async throws {
        try await seedAccountAndSite()

        let transport = try StubSaveProfileTransport(getSite: .fake())
        let service = makeService(accountIsSignedOut: false, transport: transport)

        try await service.saveProfile(
            displayName: "Ada Lovelace",
            bio: "First programmer.",
            avatar: "https://example.com/pictrs/image/avatar.png",
            showScores: false,
            showBotAccounts: false,
            showReadPosts: true,
            showAvatars: true,
            defaultListingType: .Subscribed
        )

        #expect(
            transport.didSendSaveUserSettings,
            "saveProfile should call the saveUserSettings api when signed in"
        )
        #expect(
            transport.didSendGetSite,
            "saveProfile should refresh the local profile via getSite after saving"
        )
    }

    @Test
    func saveProfile_signedIn_pushesEditedFields() async throws {
        try await seedAccountAndSite()

        let transport = try StubSaveProfileTransport(getSite: .fake())
        let service = makeService(accountIsSignedOut: false, transport: transport)

        try await service.saveProfile(
            displayName: "Ada Lovelace",
            bio: "First programmer.",
            avatar: "https://example.com/pictrs/image/avatar.png",
            showScores: false,
            showBotAccounts: false,
            showReadPosts: true,
            showAvatars: true,
            defaultListingType: .Subscribed
        )

        let body = try #require(transport.saveUserSettingsBody)
        #expect(body["display_name"] as? String == "Ada Lovelace")
        #expect(body["bio"] as? String == "First programmer.")
        #expect(body["avatar"] as? String == "https://example.com/pictrs/image/avatar.png")
        #expect(body["show_scores"] as? Bool == false)
        #expect(body["show_bot_accounts"] as? Bool == false)
        #expect(body["show_read_posts"] as? Bool == true)
        #expect(body["show_avatars"] as? Bool == true)
        #expect(body["default_listing_type"] as? String == "Subscribed")
    }

    // MARK: Signed out

    @Test
    func saveProfile_signedOut_throwsRequiresAuthentication() async throws {
        let transport = try StubSaveProfileTransport(getSite: .fake())
        let service = makeService(accountIsSignedOut: true, transport: transport)

        await #expect(throws: LemmyServiceError.self) {
            try await service.saveProfile(
                displayName: "Ada Lovelace",
                bio: "First programmer.",
                avatar: nil,
                showScores: true,
                showBotAccounts: true,
                showReadPosts: true,
                showAvatars: true,
                defaultListingType: .All
            )
        }

        #expect(
            !transport.didSendSaveUserSettings,
            "saveProfile must not call the api when the account is signed out"
        )
    }
}
