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

/// Stubs `ClientTransport` for the `saveUserSettings` operation, recording every
/// `banner` value seen across the request bodies. A banner removal issues its own
/// `saveUserSettings(banner: "")` (the v3 neutral remove path) ahead of the
/// text-settings call, so a single "most recent body" capture isn't enough — the
/// test asserts that one of the calls cleared the banner. The `getSite` that
/// `saveProfile` issues after a successful save is allowed to fail; `saveProfile`
/// catches that error silently.
private final class StubSaveUserSettingsTransport: ClientTransport, @unchecked Sendable {
    /// Every `banner` value decoded from a `saveUserSettings` body, in order.
    /// A `""` entry is a banner clear; an absent/null banner is a `nil` entry.
    private(set) var bannerValues: [String?] = []
    private(set) var didCallSaveUserSettings = false

    func send(
        _: HTTPRequest,
        body: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch operationID {
        case "saveUserSettings":
            didCallSaveUserSettings = true

            // Collect the body bytes so we can decode the JSON payload.
            if let body {
                var bytes = Data()
                for try await chunk in body {
                    bytes.append(contentsOf: chunk)
                }
                if let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                    bannerValues.append(json["banner"] as? String)
                }
            }

            let successJSON = Data(#"{"success":true}"#.utf8)
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(successJSON))

        default:
            // Silently return a 500 for anything else (e.g. getSite).
            // saveProfile catches the subsequent fetchSiteInfo failure as best-effort.
            return (HTTPResponse(status: .internalServerError), nil)
        }
    }
}

@MainActor
struct SaveProfileBannerTests {
    private let keychainId = "keychain-save-profile-banner"

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    /// Seeds instance + site + person + account so `setAccountProfile` can
    /// resolve the linked `PersonRecord` and write back to it.
    private func seedAccountWithPerson() async throws {
        let keychainId = keychainId
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)

            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)

            var person = PersonRecord(
                siteId: site.id!,
                personId: 1,
                name: "alice",
                actorId: "https://example.com/u/alice"
            )
            person.bannerUrl = "https://x/old-banner.jpg"
            try person.insert(db)

            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: false
            )
            account.personId = person.id!
            try account.insert(db)
        }
    }

    /// Reads the `PersonRecord` linked to the test account.
    private func fetchPerson() async throws -> PersonRecord? {
        let keychainId = keychainId
        return try await appDatabase.writer.read { db in
            guard let account = try AccountRecord
                .filter(Column("accountKeychainId") == keychainId)
                .fetchOne(db),
                let personId = account.personId
            else { return nil }
            return try PersonRecord.fetchOne(db, key: personId)
        }
    }

    // MARK: - Tests

    /// Removing the banner both pushes the removal to the server (on v3 a
    /// `saveUserSettings` carrying `banner: ""`) and clears the local
    /// `PersonRecord.bannerUrl` mirror, so the Account tab header reverts
    /// immediately.
    @Test
    func saveProfile_removedBanner_pushesRemovalAndClearsMirror() async throws {
        try await seedAccountWithPerson()

        let transport = StubSaveUserSettingsTransport()
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            transport: transport
        )

        try await service.saveProfile(
            displayName: nil,
            bio: nil,
            avatar: .unchanged,
            banner: .removed,
            showScores: false,
            showBotAccounts: false,
            showReadPosts: false,
            showAvatars: false,
            defaultListingType: .All
        )

        // (a) The removal reached the server as a banner cleared to "".
        #expect(transport.didCallSaveUserSettings, "saveProfile should call saveUserSettings")
        #expect(
            transport.bannerValues.contains(""),
            "a banner removal should push saveUserSettings with banner cleared to an empty string"
        )

        // (b) The local PersonRecord banner mirror was cleared.
        let person = try await fetchPerson()
        #expect(
            person?.bannerUrl == nil,
            "saveProfile must clear PersonRecord.bannerUrl on a banner removal"
        )
    }
}
