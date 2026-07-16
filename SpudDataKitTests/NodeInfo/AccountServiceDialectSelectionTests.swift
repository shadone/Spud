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

/// Covers `AccountService.resolvedApiVersion(forKeychainId:)` selecting the
/// `.piefed` LemmyKit dialect for an account whose home host NodeInfo has
/// cached as PieFed software (see `NodeInfoCacheRecord`) -- exercised through
/// the public `lemmyService(forAccountKeychainId:)` (which calls the private
/// `resolvedApiVersion` on every access), mirroring
/// `AccountServiceApiVersionSelfHealingTests`'s pattern of inspecting the
/// built `LemmyService`'s `api.apiVersion`.
@MainActor
struct AccountServiceDialectSelectionTests {
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
            site.version = siteVersion
            try site.update(db)
        }
        return keychainId
    }

    /// A host NodeInfo has cached as PieFed resolves the `.piefed` dialect —
    /// even though the persisted site version ("1.7.5") is a valid
    /// Lemmy-1.x-shaped string that would otherwise resolve `.v4`. The PieFed
    /// check must run BEFORE the Lemmy version parse, not merely override its
    /// result: PieFed's own version numbering is not on the Lemmy scale.
    @Test
    func lemmyService_nodeInfoDetectedPiefed_resolvesPiefedDialect() async throws {
        let sut = makeSUT()
        let instance = try #require(InstanceActorId(from: "https://piefed.example"))
        let keychainId = try seedAccount(instance: instance, siteVersion: "1.7.5")
        try appDatabase.seedNodeInfoCacheForUITests(
            host: "piefed.example",
            softwareName: "piefed",
            softwareVersion: "1.7.5"
        )

        let service = try #require(sut.lemmyService(forAccountKeychainId: keychainId) as? LemmyService)
        let version = await service.api.apiVersion
        #expect(version == .piefed)
    }

    /// (Task 10, item 1) The PieFed detection is memoized per keychainId after
    /// the first `lemmyService` access, so a second access must NOT re-read the
    /// NodeInfo cache. `AppDatabase` is `final` (no protocol seam to inject a
    /// counting spy through), so this is observed BEHAVIORALLY instead: mutate
    /// the underlying `nodeInfoCache` row directly (bypassing the memo) between
    /// two accesses. If the second access re-read the cache, the account would
    /// flip to non-PieFed (and resolve via the Lemmy-version parse instead,
    /// landing on `.v4` for "1.7.5") -- it stays `.piefed`, and the SAME cached
    /// `LemmyService` instance is reused, proving no re-derivation happened.
    @Test
    func lemmyService_secondCall_servesMemoizedPiefedDetection_noNodeInfoCacheReRead() async throws {
        let sut = makeSUT()
        let instance = try #require(InstanceActorId(from: "https://piefed-memo.example"))
        let keychainId = try seedAccount(instance: instance, siteVersion: "1.7.5")
        try appDatabase.seedNodeInfoCacheForUITests(
            host: "piefed-memo.example",
            softwareName: "piefed",
            softwareVersion: "1.7.5"
        )

        let first = try #require(sut.lemmyService(forAccountKeychainId: keychainId) as? LemmyService)
        #expect(await first.api.apiVersion == .piefed)

        // Correct the underlying row to "lemmy" behind the memo's back.
        try await appDatabase.writer.write { db in
            try db.execute(
                sql: "UPDATE nodeInfoCache SET softwareName = ? WHERE host = ?",
                arguments: ["lemmy", "piefed-memo.example"]
            )
        }

        let second = try #require(sut.lemmyService(forAccountKeychainId: keychainId) as? LemmyService)
        let secondVersion = await second.api.apiVersion
        #expect(secondVersion == .piefed, "the memoized PieFed detection must be served without re-reading the NodeInfo cache")
        #expect(second === first, "an unchanged resolved apiVersion must reuse the cached service, not rebuild it")
    }

    /// A host with no NodeInfo cache row at all (never probed) is unaffected —
    /// falls through to the existing Lemmy-version-based resolution exactly as
    /// before this change.
    @Test
    func lemmyService_noNodeInfoRow_resolvesByVersionAsBefore() async throws {
        let sut = makeSUT()
        let instance = try #require(InstanceActorId(from: "https://lemmy-v4.example"))
        let keychainId = try seedAccount(instance: instance, siteVersion: "1.0.0")

        let service = try #require(sut.lemmyService(forAccountKeychainId: keychainId) as? LemmyService)
        let version = await service.api.apiVersion
        #expect(version == .v4)
    }

    /// (Phase 2 review fix) A never-probed host must NOT memoize its
    /// fall-through `false` as a permanent "not PieFed" verdict — a NodeInfo
    /// probe that lands AFTER the first `lemmyService` access is picked up on
    /// the very next access, not masked for the rest of the process's
    /// lifetime. This is exactly the case that mattered for a browse account
    /// whose home-connection NodeInfo probe failed (or hadn't landed) once and
    /// then succeeded later: without this, `isPiefed(forKeychainId:)` would
    /// have pinned `false` on the first, unresolved call and silently
    /// disabled PieFed dialect detection for that account until relaunch.
    @Test
    func lemmyService_nodeInfoRowArrivesAfterFirstAccess_secondAccessPicksUpPiefed() async throws {
        let sut = makeSUT()
        let instance = try #require(InstanceActorId(from: "https://piefed-late-probe.example"))
        let keychainId = try seedAccount(instance: instance, siteVersion: "0.19.11")

        // First access: no NodeInfo row yet -- falls through to the
        // Lemmy-version parse and resolves .v3. Must NOT memoize this as a
        // resolved "not PieFed" verdict.
        let first = try #require(sut.lemmyService(forAccountKeychainId: keychainId) as? LemmyService)
        #expect(await first.api.apiVersion == .v3)

        // A NodeInfo probe lands after the first access.
        try appDatabase.seedNodeInfoCacheForUITests(
            host: "piefed-late-probe.example",
            softwareName: "piefed",
            softwareVersion: "1.7.5"
        )

        let second = try #require(sut.lemmyService(forAccountKeychainId: keychainId) as? LemmyService)
        let secondVersion = await second.api.apiVersion
        #expect(
            secondVersion == .piefed,
            "a NodeInfo probe landing after an unresolved first access must be picked up, not masked by a pinned-false memo"
        )
    }

    /// A host NodeInfo has cached as Lemmy (not PieFed) also falls through to
    /// the Lemmy-version-based resolution — the NodeInfo check only ever
    /// short-circuits to `.piefed`, it never forces `.v3`/`.v4` either way.
    @Test
    func lemmyService_nodeInfoDetectedLemmy_resolvesByVersion() async throws {
        let sut = makeSUT()
        let instance = try #require(InstanceActorId(from: "https://lemmy-v3.example"))
        let keychainId = try seedAccount(instance: instance, siteVersion: "0.19.11")
        try appDatabase.seedNodeInfoCacheForUITests(
            host: "lemmy-v3.example",
            softwareName: "lemmy",
            softwareVersion: "0.19.11"
        )

        let service = try #require(sut.lemmyService(forAccountKeychainId: keychainId) as? LemmyService)
        let version = await service.api.apiVersion
        #expect(version == .v3)
    }
}
