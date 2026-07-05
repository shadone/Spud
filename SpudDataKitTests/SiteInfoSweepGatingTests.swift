//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import SpudUtilKit
import Testing
@testable import SpudDataKit

struct SiteInfoSweepGatingTests {
    private func makeSite(_ appDatabase: AppDatabase, host: String, failures: Int = 0, nextAttemptAt: Date? = nil) async throws -> Int64 {
        try await appDatabase.writer.write { db in
            var inst = InstanceRecord(actorId: "https://\(host)", createdAt: Date(), updatedAt: Date())
            try inst.insert(db)
            var site = SiteRecord(
                instanceId: inst.id!,
                siteInfoConsecutivePermanentFailures: failures,
                siteInfoNextAttemptAt: nextAttemptAt
            )
            try site.insert(db)
            return site.id!
        }
    }

    private func addSignedOut(_ appDatabase: AppDatabase, siteId: Int64, keychainId: String, isEphemeral: Bool) async throws {
        try await appDatabase.writer.write { db in
            var acct = AccountRecord(siteId: siteId, accountKeychainId: keychainId, isSignedOutAccountType: true, isEphemeral: isEphemeral)
            try acct.insert(db)
        }
    }

    @Test
    func ephemeralAccountsAreExcluded() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let s1 = try await makeSite(appDatabase, host: "wanted.example")
        try await addSignedOut(appDatabase, siteId: s1, keychainId: "wanted", isEphemeral: false)
        let s2 = try await makeSite(appDatabase, host: "browse.example")
        try await addSignedOut(appDatabase, siteId: s2, keychainId: "browse", isEphemeral: true)
        let rows = try await appDatabase.signedOutAccountsAwaitingSiteInfo(now: Date(timeIntervalSince1970: 10000))
        #expect(rows.map(\.keychainId) == ["wanted"])
        #expect(rows.first?.siteId == s1)
    }

    @Test
    func abandonedSitesAreExcluded() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let s = try await makeSite(appDatabase, host: "waf.example", failures: AppDatabase.siteInfoGiveUpThreshold)
        try await addSignedOut(appDatabase, siteId: s, keychainId: "waf", isEphemeral: false)
        let rows = try await appDatabase.signedOutAccountsAwaitingSiteInfo(now: Date(timeIntervalSince1970: 10000))
        #expect(rows.isEmpty)
    }

    @Test
    func backoffNotYetElapsedIsExcluded() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let future = Date(timeIntervalSince1970: 20000)
        let s = try await makeSite(appDatabase, host: "slow.example", failures: 1, nextAttemptAt: future)
        try await addSignedOut(appDatabase, siteId: s, keychainId: "slow", isEphemeral: false)
        let early = try await appDatabase.signedOutAccountsAwaitingSiteInfo(now: Date(timeIntervalSince1970: 10000))
        #expect(early.isEmpty)
        let late = try await appDatabase.signedOutAccountsAwaitingSiteInfo(now: Date(timeIntervalSince1970: 30000))
        #expect(late.map(\.keychainId) == ["slow"])
    }

    @Test
    func ownerlessSiteGatingAndSiteId() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let s = try await makeSite(appDatabase, host: "ownerless.example")
        let rows = try await appDatabase.ownerlessSitesAwaitingInfo(now: Date(timeIntervalSince1970: 10000))
        #expect(rows.count == 1)
        #expect(rows.first?.siteId == s)
        #expect(rows.first?.actorId.actorId == "https://ownerless.example")
    }
}
