//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import Testing
@testable import SpudDataKit

/// Verifies the three-state semantics of the `banner:` parameter added to
/// `setAccountProfile`: non-nil URL sets it, empty string clears it, and nil
/// (omitted) leaves the existing value unchanged.
struct SetAccountProfileBannerTests {
    // MARK: - Helpers

    /// Seeds an instance, site, person, and account and links them together.
    /// The person starts with the supplied `bannerUrl` (nil = no banner stored).
    private func seedAccountWithPerson(
        keychainId: String,
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

    /// Reads back the `PersonRecord` linked to the given keychainId.
    private func fetchPerson(keychainId: String, from appDatabase: AppDatabase) async throws -> PersonRecord? {
        try await appDatabase.writer.read { db in
            guard let account = try AccountRecord
                .filter(Column("accountKeychainId") == keychainId)
                .fetchOne(db),
                let personId = account.personId
            else { return nil }
            return try PersonRecord.fetchOne(db, key: personId)
        }
    }

    // MARK: - Tests

    /// Passing a URL string sets `person.bannerUrl` to that string.
    @Test
    func setAccountProfile_bannerUrl_setsWhenNonEmpty() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let keychainId = "keychain-banner-set-test"

        try await seedAccountWithPerson(keychainId: keychainId, in: appDatabase)

        try await appDatabase.setAccountProfile(
            forKeychainId: keychainId,
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

        let person = try await fetchPerson(keychainId: keychainId, from: appDatabase)
        #expect(person?.bannerUrl == "https://x/b.jpg")
    }

    /// Passing an empty string clears `person.bannerUrl` (stores nil).
    @Test
    func setAccountProfile_bannerUrl_clearsWhenEmpty() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let keychainId = "keychain-banner-clear-test"

        try await seedAccountWithPerson(
            keychainId: keychainId,
            bannerUrl: "https://old/banner.jpg",
            in: appDatabase
        )

        try await appDatabase.setAccountProfile(
            forKeychainId: keychainId,
            displayName: nil,
            bio: nil,
            avatar: nil,
            banner: "",
            showScores: false,
            showBotAccounts: false,
            showReadPosts: false,
            showAvatars: false,
            defaultListingType: .All
        )

        let person = try await fetchPerson(keychainId: keychainId, from: appDatabase)
        #expect(person?.bannerUrl == nil)
    }

    /// Omitting `banner` (nil, the default) leaves the existing `person.bannerUrl`
    /// untouched — this is the nil=leave-unchanged semantic that prevents an
    /// in-flight editor from wiping a banner it never loaded.
    @Test
    func setAccountProfile_bannerUrl_unchangedWhenOmitted() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let keychainId = "keychain-banner-unchanged-test"

        try await seedAccountWithPerson(
            keychainId: keychainId,
            bannerUrl: "https://existing/banner.jpg",
            in: appDatabase
        )

        try await appDatabase.setAccountProfile(
            forKeychainId: keychainId,
            displayName: nil,
            bio: nil,
            avatar: nil,
            // banner deliberately omitted — defaults to nil
            showScores: false,
            showBotAccounts: false,
            showReadPosts: false,
            showAvatars: false,
            defaultListingType: .All
        )

        let person = try await fetchPerson(keychainId: keychainId, from: appDatabase)
        #expect(person?.bannerUrl == "https://existing/banner.jpg")
    }
}
