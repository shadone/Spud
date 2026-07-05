//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct SiteInfoGiveUpTests {
    private func seedSite(_ appDatabase: AppDatabase) async throws -> Int64 {
        try await appDatabase.writer.write { db in
            var inst = InstanceRecord(actorId: "https://x.example", createdAt: Date(), updatedAt: Date())
            try inst.insert(db)
            var site = SiteRecord(instanceId: inst.id!)
            try site.insert(db)
            return site.id!
        }
    }

    private func site(_ appDatabase: AppDatabase, _ id: Int64) async throws -> SiteRecord {
        let record = try await appDatabase.writer.read { db in try SiteRecord.fetchOne(db, key: id) }
        return try #require(record)
    }

    @Test
    func permanentFailureIncrementsAndSchedulesBackoff() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let siteId = try await seedSite(appDatabase)
        let now = Date(timeIntervalSince1970: 1000)
        let count = try appDatabase.recordSiteInfoPermanentFailure(siteId: siteId, now: now)
        #expect(count == 1)
        let s = try await site(appDatabase, siteId)
        #expect(s.siteInfoConsecutivePermanentFailures == 1)
        let expected = now.addingTimeInterval(SchedulerBackoff.backoffDelay(failureCount: 1))
        #expect(s.siteInfoNextAttemptAt == expected)
    }

    @Test
    func transientFailureLeavesCountAndSchedulesShortRetry() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let siteId = try await seedSite(appDatabase)
        _ = try appDatabase.recordSiteInfoPermanentFailure(siteId: siteId, now: Date(timeIntervalSince1970: 0))
        let now = Date(timeIntervalSince1970: 5000)
        try appDatabase.recordSiteInfoTransientFailure(siteId: siteId, now: now)
        let s = try await site(appDatabase, siteId)
        #expect(s.siteInfoConsecutivePermanentFailures == 1, "transient must not increment the permanent count")
        #expect(s.siteInfoNextAttemptAt == now.addingTimeInterval(300))
    }

    @Test
    func successResetsGiveUpState() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let siteId = try await seedSite(appDatabase)
        _ = try appDatabase.recordSiteInfoPermanentFailure(siteId: siteId, now: Date(timeIntervalSince1970: 0))
        try await appDatabase.writer.write { db in
            try appDatabase.resetSiteInfoGiveUpSync(siteId: siteId, db: db)
        }
        let s = try await site(appDatabase, siteId)
        #expect(s.siteInfoConsecutivePermanentFailures == 0)
        #expect(s.siteInfoNextAttemptAt == nil)
    }
}
