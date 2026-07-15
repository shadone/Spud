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
