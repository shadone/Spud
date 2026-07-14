//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

private actor CallLog {
    var names: [String] = []
    func record(_ name: String) {
        names.append(name)
    }
}

private struct FakeResolver: MetaCommunityResolving {
    /// name -> resolved candidate (nil = not found on the instance).
    let table: [String: ResolvedMetaCandidate]
    let log: CallLog?
    func resolveCandidate(
        name: String, onHost _: String, forAccountKeychainId _: String
    ) async -> ResolvedMetaCandidate? {
        await log?.record(name)
        return table[name]
    }
}

struct MetaCommunityServiceTests {
    /// `AccountRecord.siteId` is a NOT NULL foreign key to `site`, which in turn
    /// has a NOT NULL foreign key to `instance` — so seeding a bare account
    /// requires standing up an instance and a site first (mirrors the pattern in
    /// `InstanceMetaCommunityRecordTests.makeAccount`). `actorId`/`siteName`/
    /// `keychainId` default to the original fixed values so existing call sites
    /// are unaffected.
    private func seededAccount(
        _ db: AppDatabase,
        actorId: String = "https://tchncs.de",
        siteName: String? = nil,
        keychainId: String = "kc-1"
    ) throws -> Int64 {
        try db.writer.write { d in
            var instance = InstanceRecord(actorId: actorId)
            try instance.insert(d)

            var site = try SiteRecord(instanceId: #require(instance.id), name: siteName)
            try site.insert(d)

            var a = try AccountRecord(siteId: #require(site.id), accountKeychainId: keychainId)
            try a.insert(d)
            return try #require(a.id)
        }
    }

    @Test
    func resolvesClassifiesAndCachesMetaOnly() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try seededAccount(db)
        let resolver = FakeResolver(table: [
            "meta": .init(name: "meta", title: "Meta", actorId: "https://tchncs.de/c/meta", instanceHost: "tchncs.de"),
            "photography": .init(name: "photography", title: "Photography", actorId: "https://tchncs.de/c/photography", instanceHost: "tchncs.de"),
        ], log: nil)
        let service = MetaCommunityService(
            resolver: resolver, appDatabase: db, freshness: 3600,
            candidateNames: ["meta", "photography", "doesnotexist"]
        )

        await service.refreshInstance(host: "tchncs.de", siteName: "tchncs", forAccountKeychainId: "kc-1")

        // Only "meta" classifies as meta and exists; "photography" resolves but is
        // not meta; "doesnotexist" returns nil.
        #expect(db.metaCommunityFreshnessSync(forAccountId: accountId, instanceHost: "tchncs.de") != nil)
        let count = try await db.writer.read { d in
            try InstanceMetaCommunityRecord.filter(Column("accountId") == accountId).fetchCount(d)
        }
        #expect(count == 1)
    }

    @Test
    func skipsWhenCacheIsFresh() async throws {
        let db = try AppDatabase.inMemory()
        _ = try seededAccount(db)
        let log = CallLog()
        let resolver = FakeResolver(table: [
            "meta": .init(name: "meta", title: "Meta", actorId: "https://tchncs.de/c/meta", instanceHost: "tchncs.de"),
        ], log: log)
        let service = MetaCommunityService(
            resolver: resolver, appDatabase: db, freshness: 3600, candidateNames: ["meta"]
        )

        await service.refreshInstance(host: "tchncs.de", siteName: "tchncs", forAccountKeychainId: "kc-1")
        let firstCalls = await log.names.count
        await service.refreshInstance(host: "tchncs.de", siteName: "tchncs", forAccountKeychainId: "kc-1")
        let secondCalls = await log.names.count
        #expect(firstCalls > 0)
        #expect(secondCalls == firstCalls) // second call skipped by freshness
    }

    @Test
    func probesInstanceDomainLabelAndHomeSiteNameToken() async throws {
        let db = try AppDatabase.inMemory()
        _ = try seededAccount(
            db, actorId: "https://discuss.tchncs.de", siteName: "Chonkers", keychainId: "kc-tchncs"
        )
        let log = CallLog()
        // Empty table: nothing resolves, so this only exercises which names
        // get PROBED (the resolver call log), not classification/caching.
        let resolver = FakeResolver(table: [:], log: log)
        let service = MetaCommunityService(
            resolver: resolver, appDatabase: db, freshness: 3600, candidateNames: ["meta"]
        )

        await service.refreshInstance(host: "discuss.tchncs.de", siteName: nil, forAccountKeychainId: "kc-tchncs")

        let names = await log.names
        // Fix 1: the instance's primary domain label ("tchncs") is probed even
        // though it's not in the fixed candidate list.
        #expect(names.contains("tchncs"))
        // Fix 2: with `siteName` nil, the service resolves the home site's
        // name from the DB (SiteRecord.name = "Chonkers") and probes its
        // collapsed token too.
        #expect(names.contains("chonkers"))
        // The original fixed candidate is still probed.
        #expect(names.contains("meta"))
    }

    @Test
    func noOpsWhenAccountNotFound() async throws {
        let db = try AppDatabase.inMemory()
        let log = CallLog()
        let resolver = FakeResolver(table: [
            "meta": .init(name: "meta", title: "Meta", actorId: "https://tchncs.de/c/meta", instanceHost: "tchncs.de"),
        ], log: log)
        let service = MetaCommunityService(
            resolver: resolver, appDatabase: db, freshness: 3600, candidateNames: ["meta"]
        )

        await service.refreshInstance(host: "tchncs.de", siteName: "tchncs", forAccountKeychainId: "no-such-account")

        #expect(await log.names.isEmpty)
    }
}
