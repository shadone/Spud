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

/// Stubs `ClientTransport` for the `saveUserSettings` operation, recording
/// the `banner` field from the request body so the test can assert that
/// `saveProfile(banner:)` threads the value all the way to the API call.
/// The `getSite` that `saveProfile` issues after a successful save is
/// allowed to fail; `saveProfile` catches that error silently.
private final class StubSaveUserSettingsTransport: ClientTransport, @unchecked Sendable {
    /// The `banner` value decoded from the most recent `saveUserSettings` body.
    /// `nil` means the operation hasn't been called yet, or `banner` was absent.
    private(set) var capturedBanner: String?
    private(set) var didCallSaveUserSettings = false

    func send(
        _ request: HTTPRequest,
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
                    // `banner` is present and non-null only when a real URL was passed;
                    // nil/absent means "leave unchanged" on the Lemmy side.
                    capturedBanner = json["banner"] as? String
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

    /// `saveProfile(banner:)` mirrors `banner` onto the local `PersonRecord.bannerUrl`
    /// via `setAccountProfile(banner:)`. NOTE: v4 removed avatar/banner from
    /// saveUserSettings (dedicated upload endpoints now), so the neutral
    /// saveUserSettings no longer forwards the banner to the server — only the local
    /// mirror is applied. See the Phase 6 report follow-ups.
    @Test
    func saveProfile_banner_mirroredLocallyButNotPushed() async throws {
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
            avatar: nil,
            banner: "https://x/b.jpg",
            showScores: false,
            showBotAccounts: false,
            showReadPosts: false,
            showAvatars: false,
            defaultListingType: .All
        )

        // (a) saveUserSettings is still called (for the other fields), but the
        // neutral surface no longer forwards the banner to the server.
        #expect(transport.didCallSaveUserSettings, "saveProfile should call saveUserSettings")
        #expect(
            transport.capturedBanner == nil,
            "the neutral saveUserSettings no longer forwards banner (v4 dropped it)"
        )

        // (b) The local PersonRecord was updated.
        let person = try await fetchPerson()
        #expect(
            person?.bannerUrl == "https://x/b.jpg",
            "saveProfile must mirror banner onto PersonRecord.bannerUrl"
        )
    }
}
