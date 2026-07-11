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

/// Covers importing the account's server-side default post sort from a neutral
/// `MyUser` into `AccountRecord.defaultSortType`. The neutral surface carries
/// the sort un-fused (a `PostSort` + optional `TimeRange`); the importer re-fuses
/// it into the stored v3 `SortType` raw value.
@MainActor
struct AccountImporterDefaultSortTests {
    private let keychainId = "kc-default-sort"

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    private func makeSite() async throws -> Int64 {
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            return site.id!
        }
    }

    private func myUser(defaultSort: PostSort?, defaultTimeRange: TimeRange?) -> LemmyKit.MyUser {
        LemmyKit.MyUser(
            person: .fake(),
            localUserId: 1,
            emailVerified: false,
            acceptedApplication: true,
            isAdmin: false,
            showNsfw: false,
            blurNsfw: true,
            showScores: true,
            showBotAccounts: true,
            showReadPosts: true,
            showAvatars: true,
            defaultListingType: .All,
            defaultSort: defaultSort,
            defaultTimeRange: defaultTimeRange
        )
    }

    private func storedAccount() async throws -> AccountRecord? {
        let keychainId = keychainId
        return try await appDatabase.writer.read { db in
            try AccountRecord.filter(Column("accountKeychainId") == keychainId).fetchOne(db)
        }
    }

    /// Importing a `MyUser` whose default is Top-of-Week stores the fused
    /// `TopWeek` v3 sort (both the raw column and its decoded value).
    @Test
    func importMyUserWithTopWeekDefault_storesTopWeekSort() async throws {
        let siteId = try await makeSite()

        try await appDatabase.upsertAccount(
            keychainId: keychainId,
            isSignedOut: false,
            siteId: siteId,
            myUser: myUser(defaultSort: .top, defaultTimeRange: .week)
        )

        let account = try await storedAccount()
        #expect(account?.defaultSortType == "TopWeek")
        #expect(account?.resolvedDefaultSortType == .TopWeek)
    }

    /// A non-top default (e.g. Hot) maps 1:1 and ignores the time range.
    @Test
    func importMyUserWithHotDefault_storesHotSort() async throws {
        let siteId = try await makeSite()

        try await appDatabase.upsertAccount(
            keychainId: keychainId,
            isSignedOut: false,
            siteId: siteId,
            myUser: myUser(defaultSort: .hot, defaultTimeRange: nil)
        )

        let account = try await storedAccount()
        #expect(account?.defaultSortType == "Hot")
    }

    /// When the imported `MyUser` reports no default sort, the previously stored
    /// value is preserved (not clobbered to nil).
    @Test
    func importMyUserWithNilDefault_preservesStoredSort() async throws {
        let siteId = try await makeSite()

        // First import stores TopWeek.
        try await appDatabase.upsertAccount(
            keychainId: keychainId,
            isSignedOut: false,
            siteId: siteId,
            myUser: myUser(defaultSort: .top, defaultTimeRange: .week)
        )

        // A later import with no default must leave TopWeek in place.
        try await appDatabase.upsertAccount(
            keychainId: keychainId,
            isSignedOut: false,
            siteId: siteId,
            myUser: myUser(defaultSort: nil, defaultTimeRange: nil)
        )

        let account = try await storedAccount()
        #expect(account?.defaultSortType == "TopWeek")
    }
}
