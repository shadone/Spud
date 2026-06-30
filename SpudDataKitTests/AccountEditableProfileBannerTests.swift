//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import Testing
@testable import SpudDataKit

struct AccountEditableProfileBannerTests {
    // MARK: - Helpers

    /// Seeds an instance, site, and account with the given keychainId and optionally
    /// links a person row carrying the supplied avatar/banner URLs.
    /// Returns the keychainId for convenience.
    private func seedAccountWithPerson(
        keychainId: String,
        avatarUrl: String? = nil,
        bannerUrl: String? = nil,
        in appDatabase: AppDatabase
    ) async throws {
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)

            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)

            var person = PersonRecord(
                siteId: site.id!,
                personId: 1,
                name: "alice",
                avatarUrl: avatarUrl,
                bannerUrl: bannerUrl,
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

    // MARK: - bannerUrl seeding

    /// accountEditableProfileSync populates bannerUrl from the linked PersonRecord.
    @Test
    func accountEditableProfileSync_populatesBannerUrlFromPerson() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let keychainId = "keychain-banner-test"

        try await seedAccountWithPerson(
            keychainId: keychainId,
            bannerUrl: "https://lemmy.example/pictrs/image/b.jpg",
            in: appDatabase
        )

        let profile = appDatabase.accountEditableProfileSync(forKeychainId: keychainId)
        #expect(profile?.bannerUrl == "https://lemmy.example/pictrs/image/b.jpg")
    }

    /// accountEditableProfileSync returns nil bannerUrl when the person has no banner.
    @Test
    func accountEditableProfileSync_nilBannerUrlWhenPersonHasNoBanner() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let keychainId = "keychain-no-banner-test"

        try await seedAccountWithPerson(
            keychainId: keychainId,
            bannerUrl: nil,
            in: appDatabase
        )

        let profile = appDatabase.accountEditableProfileSync(forKeychainId: keychainId)
        #expect(profile?.bannerUrl == nil)
    }
}
