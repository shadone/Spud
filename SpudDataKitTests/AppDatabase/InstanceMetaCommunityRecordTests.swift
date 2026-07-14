//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct InstanceMetaCommunityRecordTests {
    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    /// `AccountRecord.siteId` is a NOT NULL foreign key to `site`, which in turn
    /// has a NOT NULL foreign key to `instance` — so seeding a bare account
    /// requires standing up an instance and a site first (mirrors the pattern in
    /// `LemmyServiceSaveTests.seedAccountSiteAndPost`).
    private func makeAccount() throws -> Int64 {
        try appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)

            var site = try SiteRecord(instanceId: #require(instance.id))
            try site.insert(db)

            var account = try AccountRecord(
                siteId: #require(site.id),
                accountKeychainId: "kc-1"
            )
            try account.insert(db)
            return try #require(account.id)
        }
    }

    @Test
    func roundTripsEveryField() throws {
        let accountId = try makeAccount()
        let record = InstanceMetaCommunityRecord(
            accountId: accountId,
            instanceHost: "discuss.tchncs.de",
            communityActorId: "https://discuss.tchncs.de/c/tchncs",
            confidence: "high",
            reason: "nameMatchesInstance",
            discoveredAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let id = try appDatabase.writer.write { db -> Int64 in
            var r = record
            try r.insert(db)
            return try #require(r.id)
        }

        let fetched = try appDatabase.writer.read { db in
            try InstanceMetaCommunityRecord.fetchOne(db, key: id)
        }
        let u = try #require(fetched)
        #expect(u.accountId == accountId)
        #expect(u.instanceHost == "discuss.tchncs.de")
        #expect(u.communityActorId == "https://discuss.tchncs.de/c/tchncs")
        #expect(u.confidence == "high")
        #expect(u.reason == "nameMatchesInstance")
        #expect(u.discoveredAt == record.discoveredAt)
    }

    @Test
    func uniqueKeyRejectsDuplicateTriple() throws {
        let accountId = try makeAccount()
        func insert() throws {
            try appDatabase.writer.write { db in
                var r = InstanceMetaCommunityRecord(
                    accountId: accountId, instanceHost: "h", communityActorId: "a",
                    confidence: "low", reason: "broadKeyword", discoveredAt: Date()
                )
                try r.insert(db)
            }
        }
        try insert()
        #expect(throws: (any Error).self) { try insert() }
    }
}
