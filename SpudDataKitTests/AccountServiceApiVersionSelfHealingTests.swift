//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import LemmyKit
import SpudUtilKit
import Testing
@testable import SpudDataKit

/// Covers the self-healing behavior of `AccountService.lemmyService(forAccountKeychainId:)`:
/// the account's resolved `ApiVersion` is re-derived from the persisted site version on
/// every access, and a cached service built against a now-stale version is evicted and
/// rebuilt, rather than being frozen for the rest of the session (initiative design D4).
@MainActor
struct AccountServiceApiVersionSelfHealingTests {
    private var appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    /// Builds an `AccountService` whose `makeApi` seam constructs a real (but
    /// never-dispatched) `LemmyApi` so its `apiVersion` can be inspected — no
    /// network call is made because the test never invokes an api method.
    private func makeSUT() -> AccountService {
        AccountService(appDatabase: appDatabase) { url, credential, apiVersion in
            LemmyApi(instanceUrl: url, credential: credential, apiVersion: apiVersion)
        }
    }

    /// Creates a signed-out account on `instance` and sets its home site's
    /// persisted `version` string directly (bypassing a real `getSite` fetch),
    /// returning the account's keychainId.
    private func seedAccount(instance: InstanceActorId, siteVersion: String) throws -> String {
        let keychainId = try appDatabase.ensureSignedOutAccountKeychainId(
            forInstance: instance,
            isServiceAccount: false
        )
        try setSiteVersion(siteVersion, forKeychainId: keychainId)
        return keychainId
    }

    /// Overwrites the persisted `site.version` string for the account matching
    /// `keychainId`, simulating a `getSite` import that mirrors a new version.
    private func setSiteVersion(_ version: String, forKeychainId keychainId: String) throws {
        try appDatabase.writer.write { db in
            guard
                let siteId = try Int64.fetchOne(db, sql: """
                        SELECT site.id FROM account
                        JOIN site ON site.id = account.siteId
                        WHERE account.accountKeychainId = ?
                    """, arguments: [keychainId]),
                var site = try SiteRecord.filter(Column("id") == siteId).fetchOne(db)
            else {
                Issue.record("expected a resolvable site for keychainId \(keychainId)")
                return
            }
            site.version = version
            try site.update(db)
        }
    }

    /// A v3 site version resolves the cached service's api to `.v3`.
    @Test
    func lemmyService_v3SiteVersion_buildsV3Service() async throws {
        let sut = makeSUT()
        let instance = try #require(InstanceActorId(from: "https://example.com"))
        let keychainId = try seedAccount(instance: instance, siteVersion: "0.19.11")

        let service = try #require(sut.lemmyService(forAccountKeychainId: keychainId) as? LemmyService)
        let version = await service.api.apiVersion
        #expect(version == .v3)
    }

    /// The core self-healing case: once the persisted site version flips from a
    /// v3-shaped string to a v4-shaped one (e.g. after a mid-session `getSite`
    /// import observes the instance upgraded), the NEXT `lemmyService` access
    /// must return a service whose api is rebuilt against `.v4` — not the stale
    /// cached `.v3` service from before the flip.
    @Test
    func lemmyService_siteVersionFlipsV3ToV4_rebuildsServiceAsV4() async throws {
        let sut = makeSUT()
        let instance = try #require(InstanceActorId(from: "https://example.com"))
        let keychainId = try seedAccount(instance: instance, siteVersion: "0.19.11")

        let before = try #require(sut.lemmyService(forAccountKeychainId: keychainId) as? LemmyService)
        #expect(await before.api.apiVersion == .v3)

        try setSiteVersion("1.0.0", forKeychainId: keychainId)

        let after = try #require(sut.lemmyService(forAccountKeychainId: keychainId) as? LemmyService)
        #expect(await after.api.apiVersion == .v4, "the service must be rebuilt against the flipped version")
        #expect(after !== before, "a stale-versioned cached service must be evicted, not reused")
    }

    /// A repeated access with no version change must keep serving the same
    /// cached instance (no needless eviction/rebuild on every call).
    @Test
    func lemmyService_unchangedSiteVersion_reusesCachedService() throws {
        let sut = makeSUT()
        let instance = try #require(InstanceActorId(from: "https://example.com"))
        let keychainId = try seedAccount(instance: instance, siteVersion: "0.19.11")

        let first = try #require(sut.lemmyService(forAccountKeychainId: keychainId) as? LemmyService)
        let second = try #require(sut.lemmyService(forAccountKeychainId: keychainId) as? LemmyService)

        #expect(first === second)
    }

    /// A freshly-added account whose site row has no version yet (no `getSite`
    /// has landed) resolves to `.v3` (the fail-open default) rather than
    /// crashing or defaulting to `.v4`. Once the version lands, the next access
    /// self-heals to `.v4` exactly like the flip case above — a newly-added
    /// account is never frozen at v3 for the rest of the session.
    @Test
    func lemmyService_accountWithNoSiteVersionYet_selfHealsOnceVersionLands() async throws {
        let sut = makeSUT()
        let instance = try #require(InstanceActorId(from: "https://example.com"))
        let keychainId = try appDatabase.ensureSignedOutAccountKeychainId(
            forInstance: instance,
            isServiceAccount: false
        )

        let before = try #require(sut.lemmyService(forAccountKeychainId: keychainId) as? LemmyService)
        #expect(await before.api.apiVersion == .v3, "no persisted version fails open to v3")

        try setSiteVersion("1.0.0", forKeychainId: keychainId)

        let after = try #require(sut.lemmyService(forAccountKeychainId: keychainId) as? LemmyService)
        #expect(await after.api.apiVersion == .v4)
        #expect(after !== before)
    }
}
