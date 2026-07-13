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
import SpudUtilKit
import Testing
@testable import SpudDataKit

/// Stub `ClientTransport` for `AccountService.reauthenticate`: answers the
/// unauthenticated `login` call plus the `getSite` refresh a successful
/// re-auth kicks off afterwards (mirrors `AccountServiceLoginTests`'s
/// `StubAuthTransport`). A `nil` `login` fixture means "reject every login
/// attempt" -- used for the wrong-password case, where the real Lemmy server
/// returns a 400 with an `incorrect_login` error body (see
/// `AccountServiceLoginErrorTests` / `LemmyServiceContentNotFoundTests` for the
/// same HTTP-400-plus-error-JSON shape).
private final class StubReauthTransport: ClientTransport, @unchecked Sendable {
    private let loginJSON: Data?
    private let siteJSON: Data?

    let getSiteSent: AsyncStream<Void>
    private let getSiteSentContinuation: AsyncStream<Void>.Continuation

    init(
        login: Lemmy.LoginResponse? = nil,
        site: Lemmy.GetSiteResponse? = nil
    ) throws {
        let encoder = JSONEncoder()
        // The generated client decodes dates via LemmyDateTranscoder, which
        // accepts the Lemmy 0.19 format: 2024-06-09T11:54:37.981990Z.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)

        loginJSON = try login.map { try encoder.encode($0) }
        siteJSON = try site.map { try encoder.encode($0) }

        (getSiteSent, getSiteSentContinuation) = AsyncStream<Void>.makeStream()
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch operationID {
        case "login":
            if let loginJSON {
                var response = HTTPResponse(status: .ok)
                response.headerFields[.contentType] = "application/json"
                return (response, HTTPBody(loginJSON))
            }
            let errorBody = Data(#"{"error":"incorrect_login"}"#.utf8)
            var response = HTTPResponse(status: .badRequest)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(errorBody))
        case "getSite":
            getSiteSentContinuation.yield(())
            if let siteJSON {
                var response = HTTPResponse(status: .ok)
                response.headerFields[.contentType] = "application/json"
                return (response, HTTPBody(siteJSON))
            }
        default:
            break
        }
        throw UnexpectedOperation(operationID: operationID)
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

/// In-memory `CredentialStore` standing in for the keychain, which the test
/// bundle can't reach (no shared-group entitlement). Duplicated from
/// `AccountServiceLoginTests`'s private `InMemoryCredentialStore` rather than
/// shared, matching this suite's existing per-file convention (see
/// `SessionReauthFlagTests`' comment on the same tradeoff).
private final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: LemmyCredential] = [:]

    func credential(forKeychainId keychainId: String) -> LemmyCredential? {
        lock.withLock { storage[keychainId] }
    }

    func setCredential(_ credential: LemmyCredential, forKeychainId keychainId: String) {
        lock.withLock { storage[keychainId] = credential }
    }

    func removeCredential(forKeychainId keychainId: String) {
        lock.withLock { _ = storage.removeValue(forKey: keychainId) }
    }
}

/// Tests for `AccountService.reauthenticate`: re-logging in to an EXISTING
/// account in place. The core contract this suite guards is "no duplicate
/// account row" -- `login`/`register` mint a fresh keychain id and account
/// row on every call, which is exactly what re-auth must NOT do.
@MainActor
struct AccountReauthenticateTests {
    private var appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    private func makeSUT(
        transport: StubReauthTransport,
        credentialStore: CredentialStore
    ) -> AccountService {
        AccountService(
            appDatabase: appDatabase,
            credentialStore: credentialStore
        ) { url, credential, _ in
            LemmyApi(instanceUrl: url, credential: credential, transport: transport)
        }
    }

    /// Seeds a real signed-in account (with a person row, so `username`
    /// resolves) already flagged `sessionNeedsReauth`, and preloads its
    /// keychain slot with a stale credential -- the starting state
    /// `reauthenticate` is meant to repair in place.
    private func makeExistingSignedInAccount(
        keychainId: String,
        credentialStore: CredentialStore
    ) async throws -> (siteId: Int64, personRowId: Int64) {
        let (siteId, personRowId) = try await appDatabase.writer.write { db -> (Int64, Int64) in
            try db.execute(sql: """
                INSERT INTO instance (actorId, createdAt, updatedAt)
                VALUES ('https://example.com', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """)
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO site (instanceId, createdAt, updatedAt)
                VALUES (?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [instanceId])
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO person (siteId, personId, name, createdAt, updatedAt)
                VALUES (?, 1, 'alice', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [siteId])
            let personRowId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO account
                    (siteId, personId, accountKeychainId, isDefault, isServiceAccount,
                     isSignedOutAccountType, isEphemeral, sessionNeedsReauth, createdAt, updatedAt)
                VALUES (?, ?, ?, 1, 0, 0, 0, 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                """, arguments: [siteId, personRowId, keychainId])
            return (siteId, personRowId)
        }
        credentialStore.setCredential(LemmyCredential(jwt: "stale.jwt.token"), forKeychainId: keychainId)
        return (siteId, personRowId)
    }

    private func totalAccountCount() throws -> Int {
        try appDatabase.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM account") ?? 0
        }
    }

    /// The core assertion: reauthenticate reuses the existing keychain id, so
    /// the account count is unchanged, the stored credential is updated in
    /// place, the re-login flag clears, and the account's identity (site,
    /// person, default-ness) is untouched.
    @Test
    func reauthenticate_success_reusesKeychainIdAndClearsFlag() async throws {
        let keychainId = "kc-reauth-success"
        let credentialStore = InMemoryCredentialStore()
        let (siteId, personRowId) = try await makeExistingSignedInAccount(
            keychainId: keychainId,
            credentialStore: credentialStore
        )

        let transport = try StubReauthTransport(login: .fake(jwt: "fresh.jwt.token"), site: .fake())
        let sut = makeSUT(transport: transport, credentialStore: credentialStore)

        let countBefore = try totalAccountCount()

        try await sut.reauthenticate(
            keychainId: keychainId,
            username: "alice",
            password: "correct-password",
            totp2faToken: nil
        )

        #expect(try totalAccountCount() == countBefore, "reauthenticate must not create a duplicate account row")

        let stored = credentialStore.credential(forKeychainId: keychainId)
        #expect(
            stored?.toString() == LemmyCredential(jwt: "fresh.jwt.token").toString(),
            "the same keychain id should now hold the fresh JWT"
        )

        let record = appDatabase.accountRecordSync(forKeychainId: keychainId)
        #expect(record?.sessionNeedsReauth == false)
        #expect(record?.isDefault == true, "identity should be preserved: still the default account")
        #expect(record?.siteId == siteId, "identity should be preserved: same site")
        #expect(record?.personId == personRowId, "identity should be preserved: same person")

        for await _ in transport.getSiteSent {
            break
        }
    }

    /// A wrong password must not silently succeed or half-apply: the typed
    /// `.invalidLogin` error propagates, the flag stays set, and the stale
    /// credential is left untouched.
    @Test
    func reauthenticate_wrongPassword_throwsInvalidLoginAndLeavesStateUnchanged() async throws {
        let keychainId = "kc-reauth-wrong-password"
        let credentialStore = InMemoryCredentialStore()
        _ = try await makeExistingSignedInAccount(keychainId: keychainId, credentialStore: credentialStore)

        // No `login` fixture -> the transport rejects every login attempt.
        let transport = try StubReauthTransport()
        let sut = makeSUT(transport: transport, credentialStore: credentialStore)

        let countBefore = try totalAccountCount()

        do {
            try await sut.reauthenticate(
                keychainId: keychainId,
                username: "alice",
                password: "wrong-password",
                totp2faToken: nil
            )
            Issue.record("expected reauthenticate to throw")
        } catch let error as AccountServiceLoginError {
            guard case .invalidLogin = error else {
                Issue.record("expected .invalidLogin, got \(error)")
                return
            }
        }

        #expect(try totalAccountCount() == countBefore)
        #expect(
            credentialStore.credential(forKeychainId: keychainId)?.toString()
                == LemmyCredential(jwt: "stale.jwt.token").toString(),
            "a failed reauthenticate must not touch the stored credential"
        )
        #expect(
            appDatabase.accountRecordSync(forKeychainId: keychainId)?.sessionNeedsReauth == true,
            "a failed reauthenticate must not clear the re-login flag"
        )
    }
}
