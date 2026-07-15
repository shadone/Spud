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

/// Stub `ClientTransport` that answers the unauthenticated `login` operation
/// with a canned `{jwt}` response. The same operationID (`"login"`) covers the
/// Lemmy v3 client (`POST /api/v3/user/login`) and the PieFed client
/// (`POST /api/alpha/user/login`), and `PiefedLoginResponse` decodes the same
/// `{jwt}` body, so one stub serves both dialects.
private final class StubLoginTransport: ClientTransport, @unchecked Sendable {
    private let loginJSON: Data

    init(jwt: String) throws {
        let encoder = JSONEncoder()
        loginJSON = try encoder.encode(Lemmy.LoginResponse.fake(jwt: jwt))
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch operationID {
        case "login":
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(loginJSON))
        default:
            // getSite (kicked off by fetchInitialSiteInfo) and anything else is
            // irrelevant to the routing assertion; fail loudly if hit.
            throw UnexpectedOperation(operationID: operationID)
        }
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

/// In-memory `CredentialStore` standing in for the keychain (unreachable from
/// the test bundle). Mirrors `AccountServiceLoginTests`'s helper.
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

/// Records the `ApiVersion` each `makeApi` call was built with, so a test can
/// assert which dialect the login request was dispatched through.
@MainActor
private final class ApiVersionRecorder {
    private(set) var versions: [LemmyKit.ApiVersion] = []
    func record(_ version: LemmyKit.ApiVersion) {
        versions.append(version)
    }
}

/// Covers `AccountService.login` resolving the login-time `ApiVersion` from the
/// NodeInfo software cache: a host cached as PieFed dispatches the login request
/// through the `.piefed` dialect (whose login route differs from Lemmy's), while
/// a Lemmy / never-probed host stays on the `.v3` compat surface. Login predates
/// the account's `getSite`, so this host-keyed resolution is the only signal
/// available at login time.
@MainActor
struct AccountServiceLoginDialectRoutingTests {
    private var appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    private func makeSUT(
        transport: StubLoginTransport,
        credentialStore: CredentialStore,
        recorder: ApiVersionRecorder
    ) -> AccountService {
        AccountService(
            appDatabase: appDatabase,
            credentialStore: credentialStore
        ) { url, credential, apiVersion in
            recorder.record(apiVersion)
            return LemmyApi(instanceUrl: url, credential: credential, transport: transport, apiVersion: apiVersion)
        }
    }

    private func firstSignedInAccount() throws -> AccountRecord? {
        try appDatabase.writer.read { db in
            try AccountRecord
                .filter(Column("isSignedOutAccountType") == false)
                .fetchOne(db)
        }
    }

    /// A host NodeInfo has cached as PieFed dispatches login through `.piefed`,
    /// and the login succeeds (the PieFed `{jwt}` is stored under the new
    /// account's keychain id).
    @Test
    func login_piefedCachedHost_dispatchesPiefedDialect() async throws {
        let recorder = ApiVersionRecorder()
        let transport = try StubLoginTransport(jwt: "piefed.jwt.token")
        let credentialStore = InMemoryCredentialStore()
        let sut = makeSUT(transport: transport, credentialStore: credentialStore, recorder: recorder)

        let instance = try #require(InstanceActorId(from: "https://piefed.example"))
        try appDatabase.seedNodeInfoCacheForUITests(
            host: "piefed.example",
            softwareName: "piefed",
            softwareVersion: "1.7.5"
        )

        try await sut.login(atInstance: instance, username: "alice", password: "secret")

        #expect(recorder.versions.first == .piefed, "login should build the api with the .piefed dialect")
        let account = try firstSignedInAccount()
        #expect(account != nil, "a signed-in account row should be created")
        let stored = try credentialStore.credential(forKeychainId: #require(account?.accountKeychainId))
        #expect(stored?.toString() == LemmyCredential(jwt: "piefed.jwt.token").toString())
    }

    /// A host with no NodeInfo cache row (never probed) stays on the `.v3`
    /// compat surface and logs in the same as before.
    @Test
    func login_noNodeInfoRow_dispatchesV3() async throws {
        let recorder = ApiVersionRecorder()
        let transport = try StubLoginTransport(jwt: "lemmy.jwt.token")
        let credentialStore = InMemoryCredentialStore()
        let sut = makeSUT(transport: transport, credentialStore: credentialStore, recorder: recorder)

        let instance = try #require(InstanceActorId(from: "https://lemmy.example"))

        try await sut.login(atInstance: instance, username: "bob", password: "secret")

        #expect(recorder.versions.first == .v3, "an unprobed host should stay on the v3 compat surface")
        #expect(try firstSignedInAccount() != nil)
    }
}
