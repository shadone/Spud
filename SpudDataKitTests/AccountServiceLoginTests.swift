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

/// Stub `ClientTransport` returning canned JSON for the unauthenticated
/// `login` / `register` operations plus the `getSite` fetch the sign-in flow
/// kicks off immediately afterwards. Records whether `getSite` was sent so the
/// "fetch site info right after sign-in" behaviour can be asserted.
private final class StubAuthTransport: ClientTransport, @unchecked Sendable {
    private let loginJSON: Data?
    private let registerJSON: Data?
    private let siteJSON: Data?

    let getSiteSent: AsyncStream<Void>
    private let getSiteSentContinuation: AsyncStream<Void>.Continuation

    init(
        login: Components.Schemas.LoginResponse? = nil,
        register: Components.Schemas.LoginResponse? = nil,
        site: Components.Schemas.GetSiteResponse? = nil
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
        registerJSON = try register.map { try encoder.encode($0) }
        siteJSON = try site.map { try encoder.encode($0) }

        (getSiteSent, getSiteSentContinuation) = AsyncStream<Void>.makeStream()
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        func ok(_ data: Data) -> (HTTPResponse, HTTPBody?) {
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(data))
        }

        switch operationID {
        case "login":
            if let loginJSON { return ok(loginJSON) }
        case "register":
            if let registerJSON { return ok(registerJSON) }
        case "getSite":
            getSiteSentContinuation.yield(())
            if let siteJSON { return ok(siteJSON) }
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
/// bundle can't reach (no shared-group entitlement). Records stored
/// credentials so the sign-in flow's persistence can be asserted.
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

    var count: Int {
        lock.withLock { storage.count }
    }
}

/// Tests for `AccountService.login` / `register` through the injectable
/// `makeApi` seam: a stub transport stands in for a live Lemmy instance, so the
/// sign-in flow (credential + account persistence, and the immediate site-info
/// fetch) is exercised without the network.
@MainActor
struct AccountServiceLoginTests {
    private var appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    private func makeSUT(
        transport: StubAuthTransport,
        credentialStore: CredentialStore
    ) -> AccountService {
        AccountService(
            appDatabase: appDatabase,
            credentialStore: credentialStore
        ) { url, credential in
            LemmyApi(instanceUrl: url, credential: credential, transport: transport)
        }
    }

    private func exampleInstance() throws -> InstanceActorId {
        try #require(InstanceActorId(from: "https://example.com"))
    }

    private func signedInAccountCount() throws -> Int {
        try appDatabase.writer.read { db in
            try AccountRecord
                .filter(Column("isSignedOutAccountType") == false)
                .fetchCount(db)
        }
    }

    private func firstSignedInAccount() throws -> AccountRecord? {
        try appDatabase.writer.read { db in
            try AccountRecord
                .filter(Column("isSignedOutAccountType") == false)
                .fetchOne(db)
        }
    }

    /// A successful login stores a signed-in default account and immediately
    /// kicks off the initial site-info fetch, so the Account screen resolves
    /// without waiting for the next SchedulerService tick.
    @Test
    func login_success_storesDefaultAccountAndFetchesSiteInfo() async throws {
        let transport = try StubAuthTransport(
            login: .fake(jwt: "a.jwt.token"),
            site: .fake()
        )
        let credentialStore = InMemoryCredentialStore()
        let sut = makeSUT(transport: transport, credentialStore: credentialStore)

        try await sut.login(atInstance: exampleInstance(), username: "alice", password: "secret")

        let account = try firstSignedInAccount()
        #expect(account != nil, "a signed-in account row should be created")
        #expect(account?.isDefault == true, "the new account becomes the default")

        // The JWT is persisted under the new account's keychain id.
        let stored = try credentialStore.credential(forKeychainId: #require(account?.accountKeychainId))
        #expect(
            stored?.toString() == LemmyCredential(jwt: "a.jwt.token").toString(),
            "the login JWT should be stored for the new account"
        )

        for await _ in transport.getSiteSent {
            break
        }
    }

    /// A 200 login response without a JWT is an internal inconsistency, not a
    /// sign-in: it throws `.missingJwt` and leaves no account behind (so the
    /// immediate site-info fetch never runs either).
    @Test
    func login_withoutJwt_throwsMissingJwtAndStoresNothing() async throws {
        let transport = try StubAuthTransport(login: .fake(jwt: nil))
        let credentialStore = InMemoryCredentialStore()
        let sut = makeSUT(transport: transport, credentialStore: credentialStore)

        do {
            try await sut.login(atInstance: exampleInstance(), username: "alice", password: "secret")
            Issue.record("expected login to throw")
        } catch let error as AccountServiceLoginError {
            guard case .missingJwt = error else {
                Issue.record("expected .missingJwt, got \(error)")
                return
            }
        }

        #expect(try signedInAccountCount() == 0)
        // swiftformat:disable:next isEmpty
        #expect(credentialStore.count == 0, "no credential should be stored")
    }

    /// Registration that returns a JWT logs the user in: it stores the account
    /// and kicks off the same immediate site-info fetch as login.
    @Test
    func register_loggedIn_storesAccountAndFetchesSiteInfo() async throws {
        let transport = try StubAuthTransport(
            register: .fake(jwt: "a.jwt.token"),
            site: .fake()
        )
        let credentialStore = InMemoryCredentialStore()
        let sut = makeSUT(transport: transport, credentialStore: credentialStore)

        let result = try await sut.register(
            atInstance: exampleInstance(),
            username: "alice",
            email: nil,
            password: "secret",
            passwordVerify: "secret",
            showNsfw: false,
            captchaUuid: nil,
            captchaAnswer: nil,
            answer: nil
        )

        #expect(result == .loggedIn)
        #expect(try signedInAccountCount() == 1)
        #expect(credentialStore.count == 1, "the registration JWT should be stored")
        for await _ in transport.getSiteSent {
            break
        }
    }
}
