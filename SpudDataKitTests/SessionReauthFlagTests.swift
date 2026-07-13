//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import HTTPTypes
import LemmyKit
import OpenAPIRuntime
import Testing
@testable import SpudDataKit

struct SessionReauthFlagTests {
    /// Inserts a real signed-in account row and returns its keychain id + rowid.
    private func makeSignedInAccount(_ db: AppDatabase) async throws -> (keychainId: String, accountId: Int64) {
        let keychainId = "kc-signed-in"
        let accountId: Int64 = try await db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO instance (actorId, createdAt, updatedAt)
                VALUES ('https://lemmy.example', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """)
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO site (instanceId, createdAt, updatedAt)
                VALUES (?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [instanceId])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account
                    (siteId, accountKeychainId, isDefault, isServiceAccount,
                     isSignedOutAccountType, isEphemeral, createdAt, updatedAt)
                VALUES (?, ?, 1, 0, 0, 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [siteId, keychainId])
            return db.lastInsertedRowID
        }
        return (keychainId, accountId)
    }

    @Test
    func migrationAddsFlagDefaultingFalse() async throws {
        let db = try AppDatabase.inMemory()
        let (keychainId, _) = try await makeSignedInAccount(db)
        let record = db.accountRecordSync(forKeychainId: keychainId)
        #expect(record?.sessionNeedsReauth == false)
    }

    @Test
    func setAndClearByKeychainId() async throws {
        let db = try AppDatabase.inMemory()
        let (keychainId, _) = try await makeSignedInAccount(db)

        try await db.setAccountSessionNeedsReauth(keychainId: keychainId, true)
        #expect(db.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == true)
        #expect(db.accountAnyNeedsReauthSync())

        try await db.setAccountSessionNeedsReauth(keychainId: keychainId, false)
        #expect(db.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == false)
        #expect(!db.accountAnyNeedsReauthSync())
    }

    @Test
    func setByAccountIdMatchesKeychainId() async throws {
        let db = try AppDatabase.inMemory()
        let (keychainId, accountId) = try await makeSignedInAccount(db)
        try await db.setAccountSessionNeedsReauth(accountId: accountId, true)
        #expect(db.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == true)
    }

    @Test
    func signedOutAccountNeverFlaggable() async throws {
        let db = try AppDatabase.inMemory()
        let keychainId = "kc-signed-out"
        try await db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO instance (actorId, createdAt, updatedAt)
                VALUES ('https://lemmy.example', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """)
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO site (instanceId, createdAt, updatedAt)
                VALUES (?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [instanceId])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account
                    (siteId, accountKeychainId, isDefault, isServiceAccount,
                     isSignedOutAccountType, isEphemeral, createdAt, updatedAt)
                VALUES (?, ?, 1, 0, 1, 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [siteId, keychainId])
        }
        // The WHERE guard makes this a no-op, not an error.
        try await db.setAccountSessionNeedsReauth(keychainId: keychainId, true)
        #expect(db.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == false)
        #expect(!db.accountAnyNeedsReauthSync())
    }

    @Test
    func accountListRowCarriesFlag() async throws {
        let db = try AppDatabase.inMemory()
        let (keychainId, _) = try await makeSignedInAccount(db)
        try await db.setAccountSessionNeedsReauth(keychainId: keychainId, true)

        var iterator = db.observeAccountListRows().makeAsyncIterator()
        let rows = await iterator.next()
        let row = rows?.first { $0.accountKeychainId == keychainId }
        #expect(row?.sessionNeedsReauth == true)
    }
}

// MARK: - Passive trigger (getSiteInfo)

/// Stub `ClientTransport` for the passive session-reauth tests below. Answers
/// `getSite` with either a canned 200 `GetSiteResponse` (JSON encoding mirrors
/// `LemmyServiceGetSiteInfoTests`'s `CountingGetSiteTransport`) or a bare HTTP
/// status with no body -- the latter reproduces a WAF-style 403 the same way
/// `LemmyServiceContentNotFoundTests`'s `NotFoundTransport` reproduces a 400.
private final class GetSiteReauthStubTransport: ClientTransport, @unchecked Sendable {
    private enum Stubbed {
        case json(Data)
        case status(HTTPResponse.Status)
    }

    private let stubbed: Stubbed

    init(getSite: Lemmy.GetSiteResponse) throws {
        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        stubbed = try .json(encoder.encode(getSite))
    }

    init(httpStatus: HTTPResponse.Status) {
        stubbed = .status(httpStatus)
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch stubbed {
        case let .json(data):
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(data))
        case let .status(status):
            return (HTTPResponse(status: status), nil)
        }
    }
}

/// Covers spec 2.2: the passive `getSiteInfo()` refresh self-heals the
/// re-login flag on every signed-in fetch. Cases A-C from the task-2 brief.
@MainActor
struct SessionReauthPassiveTriggerTests {
    /// Inserts a real signed-in account row. Duplicated from
    /// `SessionReauthFlagTests.makeSignedInAccount` (private to that suite)
    /// rather than shared, matching this file's existing per-suite convention.
    private func makeSignedInAccount(_ db: AppDatabase, keychainId: String) async throws {
        try await db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO instance (actorId, createdAt, updatedAt)
                VALUES ('https://lemmy.example', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """)
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO site (instanceId, createdAt, updatedAt)
                VALUES (?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [instanceId])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account
                    (siteId, accountKeychainId, isDefault, isServiceAccount,
                     isSignedOutAccountType, isEphemeral, createdAt, updatedAt)
                VALUES (?, ?, 1, 0, 0, 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [siteId, keychainId])
        }
    }

    /// Case A: signed-in v3 `getSite` SUCCEEDS but `my_user` is absent (the
    /// server rejected the stored token) -> the flag is SET.
    @Test
    func signedInSuccessWithoutMyUserSetsFlag() async throws {
        let keychainId = "kc-passive-case-a"
        let appDatabase = try AppDatabase.inMemory()
        let transport = try GetSiteReauthStubTransport(getSite: .fake(myUser: false))
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        _ = try await service.getSiteInfo()

        #expect(appDatabase.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == true)
    }

    /// Case B: signed-in `getSite` SUCCEEDS with `my_user` present -> the flag
    /// is CLEARED (self-heal), even though it was previously set.
    @Test
    func signedInSuccessWithMyUserClearsFlag() async throws {
        let keychainId = "kc-passive-case-b"
        let appDatabase = try AppDatabase.inMemory()
        try await makeSignedInAccount(appDatabase, keychainId: keychainId)
        try await appDatabase.setAccountSessionNeedsReauth(keychainId: keychainId, true)

        let transport = try GetSiteReauthStubTransport(getSite: .fake(myUser: true))
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        _ = try await service.getSiteInfo()

        #expect(appDatabase.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == false)
    }

    /// Case C: signed-in `getSite` throws a bare WAF 403 -> `AuthExpiry`
    /// excludes it, so the flag stays UNCHANGED (false) and the thrown error
    /// still propagates unchanged to the caller.
    @Test
    func signedInWaf403DoesNotSetFlag() async throws {
        let keychainId = "kc-passive-case-c"
        let appDatabase = try AppDatabase.inMemory()
        try await makeSignedInAccount(appDatabase, keychainId: keychainId)

        let transport = GetSiteReauthStubTransport(httpStatus: .forbidden)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        await #expect(throws: (any Error).self) {
            try await service.getSiteInfo()
        }
        #expect(appDatabase.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == false)
    }
}

// MARK: - Write-side trigger (OutboxService .permanent)

/// Covers spec 2.3: the mutation outbox flags the account on a permanent
/// auth failure and tags the emitted `OutboxFailure.isAuthExpiry`. Reuses the
/// shared `OutboxService` test fixtures from `Outbox/OutboxTestSupport.swift`
/// (`FakeOutboxPerformer`, `seedAccountAndSite`, `seedPost`) and mirrors
/// `Outbox/OutboxServiceTests.swift`'s `makeService` shape.
@MainActor
struct SessionReauthOutboxTriggerTests {
    private func makeService(
        _ appDatabase: AppDatabase,
        _ performer: FakeOutboxPerformer,
        accountId: Int64
    ) -> OutboxService {
        OutboxService(
            accountId: accountId,
            appDatabase: appDatabase,
            performer: performer,
            reachability: StaticReachabilityMonitor(isOnline: true),
            now: { 1000 },
            diagnostics: DiagnosticLogSpy(),
            instance: "lemmy.test"
        )
    }

    /// A genuine auth-expiry (`unauthorized`) permanent failure flags the
    /// account for re-login and tags the emitted failure.
    @Test
    func permanentAuthFailureFlagsAccountAndTagsFailure() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 5, voteStatus: nil)
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(.fail(LemmyApiError.unauthorized(message: nil)), for: .vote)
        let service = makeService(appDatabase, performer, accountId: accountId)

        var events: [OutboxFailure] = []
        let stream = await service.failureEvents
        let collector = Task { for await event in stream {
            events.append(event)
            break
        } }

        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))
        await collector.value

        #expect(events.first?.isAuthExpiry == true)
        #expect(appDatabase.accountRecordSync(forKeychainId: "keychain-outbox-test")?.sessionNeedsReauth == true)
    }

    /// A bare 403 (WAF/CDN, not auth) is still a `.permanent` failure class
    /// (rolled back), but `AuthExpiry` excludes it, so it must NOT flag the
    /// account or tag the failure as an auth expiry.
    @Test
    func permanentNonAuthFailureDoesNotFlagAccount() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 5, voteStatus: nil)
        let performer = FakeOutboxPerformer()
        await performer.setOutcome(.fail(LemmyApiError.unknownServerError(httpStatusCode: 403, error: nil)), for: .vote)
        let service = makeService(appDatabase, performer, accountId: accountId)

        var events: [OutboxFailure] = []
        let stream = await service.failureEvents
        let collector = Task { for await event in stream {
            events.append(event)
            break
        } }

        await service.enqueue(.init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)))
        await collector.value

        #expect(events.first?.isAuthExpiry == false)
        #expect(appDatabase.accountRecordSync(forKeychainId: "keychain-outbox-test")?.sessionNeedsReauth == false)
    }
}
