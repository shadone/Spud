//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import KeychainAccess
import LemmyKit
import OSLog
import SpudUtilKit

private let logger = Logger.accountService

@MainActor
public protocol AccountServiceType: AnyObject {
    /// Resolves (or creates) a signed-out account for `instance` and returns
    /// its `accountKeychainId`. `isServiceAccount` distinguishes the
    /// background-fetch service rows used by SchedulerService from real
    /// signed-out user accounts.
    func accountForSignedOut(
        forInstance instance: InstanceActorId,
        isServiceAccount: Bool
    ) -> String

    /// Creates (if needed) the signed-out account for `instance` and marks
    /// it as the default account.
    func signInAsSignedOut(atInstance instance: InstanceActorId)

    /// Log in to a given Lemmy instance with explicitly provided username and password.
    func login(
        atInstance instance: InstanceActorId,
        username: String,
        password: String
    ) async throws

    /// Register a new account on `instance`. On a JWT-bearing response the
    /// credential is stored and the account marked default (mirroring
    /// `login`), returning `.loggedIn`. When the instance returns a pending
    /// state (admin approval / email verification), no credential is stored
    /// and the matching `.applicationPending` / `.verifyEmail` / `.pending`
    /// result is returned for the UI to surface. Throws
    /// `AccountServiceRegisterError` on rejection.
    ///
    /// `captchaUuid` / `captchaAnswer` are passed through when the instance
    /// requires a captcha; the no-captcha path (the common case) needs neither.
    func register(
        atInstance instance: InstanceActorId,
        username: String,
        email: String?,
        password: String,
        passwordVerify: String,
        showNsfw: Bool,
        captchaUuid: String?,
        captchaAnswer: String?,
        answer: String?
    ) async throws -> AccountServiceRegisterResult

    /// Requests a password-reset email for `email` from `instance`. The reset
    /// itself is handled entirely by the server (it mails a reset link); this
    /// just triggers it. Mirrors `login` in that it uses a temporary
    /// unauthenticated api against the instance. Throws on a network/server
    /// error so the caller can surface it.
    func passwordReset(
        atInstance instance: InstanceActorId,
        email: String
    ) async throws

    /// Logs out the account matching `keychainId`: removes its keychain
    /// credential and database row, then switches the default account to
    /// another registered account (or the signed-out account for the same
    /// instance). No-op for a signed-out account.
    func logout(forAccountKeychainId keychainId: String)

    /// Removes the account matching `keychainId` from the account list: deletes
    /// its database row (and keychain credential, if signed in). Unlike
    /// `logout`, this also removes signed-out accounts, and it only re-points
    /// the default when the removed account was itself the default — so deleting
    /// a non-active account doesn't switch the user away from the one in use.
    func removeAccount(forAccountKeychainId keychainId: String)

    /// Returns the `accountKeychainId` of the current default / first non-service
    /// account, or `nil` when none exists. Read-only: never creates an account.
    /// `MainWindow` uses `nil` to decide to show onboarding instead of the tabs.
    func currentDefaultAccountKeychainId() -> String?

    /// Whether the account is the signed-out placeholder for its site. Reads
    /// `AccountRecord.isSignedOutAccountType` synchronously.
    func isSignedOut(forAccountKeychainId keychainId: String) -> Bool

    /// Resolves the account by `keychainId` and marks it default. No-op if
    /// the account isn't registered.
    func setDefaultAccount(forAccountKeychainId keychainId: String)

    /// Resolves an account suitable for `instance` and returns its
    /// `accountKeychainId`. Creates the site and a signed-out account if
    /// none exist.
    func accountKeychainId(forInstance instance: InstanceActorId) -> String

    /// Resolves the LemmyService for the account whose `accountKeychainId`
    /// matches `keychainId`. Crashes if no such account is registered.
    func lemmyService(forAccountKeychainId keychainId: String) -> LemmyServiceType

    /// The account's preferred listing type. Falls back to the site's
    /// `defaultPostListingType`, then to `.All` if neither is set.
    func defaultListingType(forAccountKeychainId keychainId: String) -> Components.Schemas.ListingType

    /// The account's preferred sort type. Falls back to `.Hot` if not set.
    func defaultSortType(forAccountKeychainId keychainId: String) -> Components.Schemas.SortType

    /// Persists the account's preferred POST sort type to its stored record so
    /// the choice survives relaunch. The value is read back by
    /// `defaultSortType(forAccountKeychainId:)`. No-op if the account isn't
    /// registered.
    func setDefaultSortType(
        _ sortType: Components.Schemas.SortType,
        forAccountKeychainId keychainId: String
    )

    /// The actor id of the instance the account is homed on (e.g. the one
    /// behind `lemmy.world`). Resolves account -> site -> instance. Returns
    /// nil when the account or its instance can't be found. Used to name the
    /// instance in feed error states.
    func instanceActorId(forAccountKeychainId keychainId: String) -> InstanceActorId?
}

@MainActor
public extension AccountServiceType {
    /// Creates a feed with the given parameters. Returns a `FeedHandle`
    /// carrying the stable `feedKey` (for GRDB observations and
    /// LemmyService.fetchFeed) and the `feedType` (for navigation/sort UI).
    /// The matching `FeedRecord` row is created lazily by the first
    /// `appendFeedPage`, so this entry point performs no I/O.
    func createFeed(
        forAccountKeychainId _: String,
        feedType: FeedType
    ) -> FeedHandle {
        FeedHandle(feedKey: UUID().uuidString, feedType: feedType)
    }

    func createDefaultFeed(forAccountKeychainId keychainId: String) -> FeedHandle {
        let feedType = FeedType.frontpage(
            listingType: defaultListingType(forAccountKeychainId: keychainId),
            sortType: defaultSortType(forAccountKeychainId: keychainId)
        )
        return FeedHandle(feedKey: UUID().uuidString, feedType: feedType)
    }

    func createFeed(
        duplicateOf existing: FeedHandle,
        forAccountKeychainId _: String,
        sortType: Components.Schemas.SortType? = nil
    ) -> FeedHandle {
        let newFeedType: FeedType = {
            switch existing.feedType {
            case let .frontpage(listingType, oldSortType):
                return .frontpage(
                    listingType: listingType,
                    sortType: sortType ?? oldSortType
                )
            case let .community(communityName, instance, oldSortType):
                return .community(
                    communityName: communityName,
                    instance: instance,
                    sortType: sortType ?? oldSortType
                )
            case let .saved(oldSortType):
                return .saved(sortType: sortType ?? oldSortType)
            }
        }()
        return FeedHandle(feedKey: UUID().uuidString, feedType: newFeedType)
    }
}

@MainActor
public protocol HasAccountService {
    var accountService: AccountServiceType { get }
}

@MainActor
public class AccountService: AccountServiceType {
    // MARK: Private

    private let appDatabase: AppDatabase

    /// Builds a `LemmyApi` for an instance url and optional credential.
    /// Injectable so the sign-in path can be unit-tested with a stub
    /// `ClientTransport` instead of a live instance; production wires up the
    /// real `URLSessionTransport`-backed api.
    private let makeApi: @MainActor (_ instanceUrl: URL, _ credential: LemmyCredential?) -> LemmyApi

    /// Persists per-account credentials. Injectable so tests exercise the
    /// sign-in flow without the shared-group keychain entitlements the test
    /// bundle lacks; production uses `KeychainCredentialStore`.
    private let credentialStore: CredentialStore

    /// Network reachability, threaded into each per-account `LemmyService` so its
    /// outbox can classify failures (offline = transient, retry on reconnect) and
    /// auto-drain when connectivity returns. Defaults to a live monitor so the
    /// many `AccountService(appDatabase:)` call sites (tests, widget) keep working.
    private let reachabilityMonitor: ReachabilityMonitoring

    private var lemmyServices: [String: LemmyService] = [:]

    // MARK: Functions

    public convenience init(
        appDatabase: AppDatabase,
        reachabilityMonitor: ReachabilityMonitoring = StaticReachabilityMonitor(isOnline: true)
    ) {
        self.init(appDatabase: appDatabase, reachabilityMonitor: reachabilityMonitor) { instanceUrl, credential in
            LemmyApi(instanceUrl: instanceUrl, credential: credential, userAgent: AppUserAgent.value)
        }
    }

    init(
        appDatabase: AppDatabase,
        credentialStore: CredentialStore = KeychainCredentialStore(),
        reachabilityMonitor: ReachabilityMonitoring = StaticReachabilityMonitor(isOnline: true),
        makeApi: @escaping @MainActor (_ instanceUrl: URL, _ credential: LemmyCredential?) -> LemmyApi
    ) {
        self.appDatabase = appDatabase
        self.credentialStore = credentialStore
        self.reachabilityMonitor = reachabilityMonitor
        self.makeApi = makeApi
    }

    public func currentDefaultAccountKeychainId() -> String? {
        assert(Thread.current.isMainThread)
        do {
            return try appDatabase.writer.read { db -> String? in
                try AccountRecord
                    .filter(Column("isServiceAccount") == false)
                    .order(sql: "isDefault DESC, id ASC")
                    .fetchOne(db)?
                    .accountKeychainId
            }
        } catch {
            logger.error("currentDefaultAccountKeychainId GRDB read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func isSignedOut(forAccountKeychainId keychainId: String) -> Bool {
        do {
            return try appDatabase.writer.read { db in
                try AccountRecord
                    .filter(Column("accountKeychainId") == keychainId)
                    .fetchOne(db)?
                    .isSignedOutAccountType ?? true
            }
        } catch {
            logger.error("Failed to read isSignedOut: \(error.localizedDescription, privacy: .public)")
            return true
        }
    }

    public func defaultListingType(forAccountKeychainId keychainId: String) -> Components.Schemas.ListingType {
        do {
            return try appDatabase.writer.read { db in
                guard
                    let account = try AccountRecord
                    .filter(Column("accountKeychainId") == keychainId)
                    .fetchOne(db)
                else { return .All }
                if
                    let raw = account.defaultListingType,
                    let value = Components.Schemas.ListingType(rawValue: raw)
                {
                    return value
                }
                if
                    let site = try SiteRecord.filter(Column("id") == account.siteId).fetchOne(db),
                    let raw = site.defaultPostListingType,
                    let value = Components.Schemas.ListingType(rawValue: raw)
                {
                    return value
                }
                return .All
            }
        } catch {
            logger.error("Failed to read defaultListingType: \(error.localizedDescription, privacy: .public)")
            return .All
        }
    }

    public func defaultSortType(forAccountKeychainId keychainId: String) -> Components.Schemas.SortType {
        do {
            return try appDatabase.writer.read { db in
                guard
                    let account = try AccountRecord
                    .filter(Column("accountKeychainId") == keychainId)
                    .fetchOne(db)
                else { return .Hot }
                return account.resolvedDefaultSortType
            }
        } catch {
            logger.error("Failed to read defaultSortType: \(error.localizedDescription, privacy: .public)")
            return .Hot
        }
    }

    public func setDefaultSortType(
        _ sortType: Components.Schemas.SortType,
        forAccountKeychainId keychainId: String
    ) {
        do {
            try appDatabase.setAccountDefaultSortType(sortType, forKeychainId: keychainId)
        } catch {
            logger.error("Failed to write defaultSortType: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func instanceActorId(forAccountKeychainId keychainId: String) -> InstanceActorId? {
        do {
            let actorIdRaw = try appDatabase.writer.read { db -> String? in
                try String.fetchOne(db, sql: """
                        SELECT instance.actorId
                        FROM account
                        JOIN site ON site.id = account.siteId
                        JOIN instance ON instance.id = site.instanceId
                        WHERE account.accountKeychainId = ?
                    """, arguments: [keychainId])
            }
            guard let actorIdRaw else { return nil }
            return InstanceActorId(from: actorIdRaw)
        } catch {
            logger.error("Failed to read instanceActorId: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func signInAsSignedOut(atInstance instance: InstanceActorId) {
        do {
            let keychainId = try appDatabase.ensureSignedOutAccountKeychainId(
                forInstance: instance,
                isServiceAccount: false
            )
            try appDatabase.setDefaultAccountSync(keychainId: keychainId)
        } catch {
            logger.error("signInAsSignedOut failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func setDefaultAccount(forAccountKeychainId keychainId: String) {
        do {
            try appDatabase.setDefaultAccountSync(keychainId: keychainId)
        } catch {
            logger.error("setDefaultAccount failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func accountKeychainId(forInstance instance: InstanceActorId) -> String {
        assert(Thread.current.isMainThread)
        do {
            return try appDatabase.bestAccountKeychainId(forInstance: instance)
        } catch {
            logger.fault("accountKeychainId(forInstance:) failed: \(error.localizedDescription, privacy: .public)")
            fatalError("accountKeychainId(forInstance:) failed: \(error)")
        }
    }

    public func accountForSignedOut(
        forInstance instance: InstanceActorId,
        isServiceAccount: Bool
    ) -> String {
        assert(Thread.current.isMainThread)
        do {
            return try appDatabase.ensureSignedOutAccountKeychainId(
                forInstance: instance,
                isServiceAccount: isServiceAccount
            )
        } catch {
            logger.fault("accountForSignedOut(forInstance:) failed: \(error.localizedDescription, privacy: .public)")
            fatalError("accountForSignedOut(forInstance:) failed: \(error)")
        }
    }

    public func lemmyService(forAccountKeychainId keychainId: String) -> LemmyServiceType {
        assert(Thread.current.isMainThread)

        if let cached = lemmyServices[keychainId] {
            return cached
        }

        let snapshot: (isSignedOut: Bool, actorId: InstanceActorId)
        do {
            snapshot = try appDatabase.writer.read { db -> (Bool, InstanceActorId) in
                guard
                    let row = try Row.fetchOne(db, sql: """
                            SELECT
                                account.isSignedOutAccountType AS isSignedOut,
                                instance.actorId               AS actorId
                            FROM account
                            JOIN site     ON site.id = account.siteId
                            JOIN instance ON instance.id = site.instanceId
                            WHERE account.accountKeychainId = ?
                        """, arguments: [keychainId])
                else {
                    fatalError("No account registered for keychainId \(keychainId)")
                }
                let isSignedOut: Bool = row["isSignedOut"]
                let actorIdRaw: String = row["actorId"]
                guard let actorId = InstanceActorId(from: actorIdRaw) else {
                    fatalError("Invalid instance actorId '\(actorIdRaw)' for account \(keychainId)")
                }
                return (isSignedOut, actorId)
            }
        } catch {
            logger.fault("lemmyService(forAccountKeychainId:) lookup failed: \(error.localizedDescription, privacy: .public)")
            fatalError("lemmyService(forAccountKeychainId:) failed: \(error)")
        }

        guard let url = snapshot.actorId.url else {
            fatalError("Failed to create URL from instance actor id '\(snapshot.actorId.actorId)'")
        }
        let credential = snapshot.isSignedOut ? nil : readCredential(forKeychainId: keychainId)
        let api = makeApi(url, credential)

        logger.debug("Creating new LemmyService for \(keychainId, privacy: .sensitive(mask: .hash))")

        let service = LemmyService(
            accountKeychainId: keychainId,
            accountIsSignedOut: snapshot.isSignedOut,
            appDatabase: appDatabase,
            api: api,
            reachability: reachabilityMonitor
        )
        lemmyServices[keychainId] = service
        return service
    }

    public func login(
        atInstance instance: InstanceActorId,
        username: String,
        password: String
    ) async throws {
        guard let url = instance.url else {
            fatalError("Failed to create URL from instance actor id '\(instance.actorId)'")
        }

        // Temporary unauthenticated api for the login request.
        let api = makeApi(url, nil)

        let response: Components.Schemas.LoginResponse
        do {
            response = try await api.login(usernameOrEmail: username, password: password)
        } catch {
            let error = AccountServiceLoginError(from: error)

            if case .invalidLogin = error {
                // this is a "good" kind of error, no need to log this
                throw error
            }

            logger.error("""
                Login failed. instance=\(instance.actorId, privacy: .public). \
                username=\(username, privacy: .sensitive(mask: .hash))
                \(String(describing: error), privacy: .public)
                """)
            throw error
        }

        guard let jwt = response.jwt else {
            throw AccountServiceLoginError.missingJwt
        }
        let keychainId = try await storeSignedInCredential(LemmyCredential(jwt: jwt), atInstance: instance)
        // Fetch the new account's site info (which carries `MyUserInfo`, and so
        // the account holder's own Person row) right now. Without this the row
        // only lands on the next periodic `SchedulerService` tick — up to five
        // minutes away — leaving the Account screen spinning until then.
        fetchInitialSiteInfo(forAccountKeychainId: keychainId)
    }

    public func register(
        atInstance instance: InstanceActorId,
        username: String,
        email: String?,
        password: String,
        passwordVerify: String,
        showNsfw: Bool,
        captchaUuid: String?,
        captchaAnswer: String?,
        answer: String?
    ) async throws -> AccountServiceRegisterResult {
        guard let url = instance.url else {
            fatalError("Failed to create URL from instance actor id '\(instance.actorId)'")
        }

        // Temporary unauthenticated api for the registration request.
        let api = makeApi(url, nil)

        let response: Components.Schemas.LoginResponse
        do {
            response = try await api.register(
                username: username,
                password: password,
                passwordVerify: passwordVerify,
                email: email,
                showNSFW: showNsfw,
                captchaUUID: captchaUuid,
                captchaAnswer: captchaAnswer,
                answer: answer
            )
        } catch {
            let error = AccountServiceRegisterError(from: error)
            logger.error("""
                Register failed. instance=\(instance.actorId, privacy: .public). \
                username=\(username, privacy: .sensitive(mask: .hash))
                \(String(describing: error), privacy: .public)
                """)
            throw error
        }

        let result = AccountServiceRegisterResult(response: response)
        if case .loggedIn = result, let jwt = response.jwt {
            let keychainId = try await storeSignedInCredential(LemmyCredential(jwt: jwt), atInstance: instance)
            fetchInitialSiteInfo(forAccountKeychainId: keychainId)
        }
        return result
    }

    public func passwordReset(
        atInstance instance: InstanceActorId,
        email: String
    ) async throws {
        guard let url = instance.url else {
            fatalError("Failed to create URL from instance actor id '\(instance.actorId)'")
        }

        // Temporary unauthenticated api for the password-reset request, mirroring
        // `login` / `register`.
        let api = makeApi(url, nil)

        do {
            _ = try await api.passwordReset(email: email)
        } catch {
            logger.error("""
                Password reset failed. instance=\(instance.actorId, privacy: .public).
                \(String(describing: error), privacy: .public)
                """)
            throw error
        }
    }

    /// Shared tail of `login` / `register`: creates the account row, marks it
    /// default, and writes the credential to the keychain.
    private func storeSignedInCredential(
        _ credential: LemmyCredential,
        atInstance instance: InstanceActorId
    ) async throws -> String {
        let keychainId = UUID().uuidString
        let (_, siteId) = try await appDatabase.ensureSite(forInstance: instance)
        _ = try await appDatabase.ensureAccount(
            keychainId: keychainId,
            siteId: siteId,
            isSignedOut: false,
            isServiceAccount: false
        )
        try await appDatabase.setDefaultAccount(keychainId: keychainId)
        writeCredential(credential, forKeychainId: keychainId)
        return keychainId
    }

    /// Kicks off the initial site/`MyUserInfo` fetch for a freshly added
    /// signed-in account so its own Person row lands within a second, instead of
    /// waiting for the next periodic `SchedulerService` tick (up to five minutes
    /// away). Fire-and-forget; the scheduler remains the backstop if it fails.
    private func fetchInitialSiteInfo(forAccountKeychainId keychainId: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await lemmyService(forAccountKeychainId: keychainId).fetchSiteInfo()
            } catch {
                logger.error("Initial site info fetch after sign-in failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func logout(forAccountKeychainId keychainId: String) {
        assert(Thread.current.isMainThread)

        guard !isSignedOut(forAccountKeychainId: keychainId) else {
            logger.debug("logout no-op for signed-out account")
            return
        }

        // Pick the account to fall back to before removing this one.
        let instanceActorId = appDatabase.accountInstanceActorIdSync(forKeychainId: keychainId)
        let fallbackKeychainId = appDatabase.fallbackAccountKeychainIdSync(excludingKeychainId: keychainId)

        // Drop the cached service so a stale authenticated api isn't reused.
        lemmyServices[keychainId] = nil

        deleteCredential(forKeychainId: keychainId)
        do {
            try appDatabase.deleteAccountSync(keychainId: keychainId)
        } catch {
            logger.error("logout failed to delete account row: \(error.localizedDescription, privacy: .public)")
        }

        // Switch the default to another account, or the signed-out account on
        // the same instance, so the app is never left without a default.
        if let fallbackKeychainId {
            setDefaultAccount(forAccountKeychainId: fallbackKeychainId)
        } else if let instanceActorId, let instance = InstanceActorId(from: instanceActorId) {
            signInAsSignedOut(atInstance: instance)
        }
    }

    public func removeAccount(forAccountKeychainId keychainId: String) {
        assert(Thread.current.isMainThread)

        let wasDefault = currentDefaultAccountKeychainId() == keychainId

        // Resolve a fallback before removing, in case this was the default.
        let instanceActorId = appDatabase.accountInstanceActorIdSync(forKeychainId: keychainId)
        let fallbackKeychainId = appDatabase.fallbackAccountKeychainIdSync(excludingKeychainId: keychainId)

        // Drop the cached service so a stale authenticated api isn't reused.
        lemmyServices[keychainId] = nil

        // Signed-out accounts have no keychain credential to clear.
        if !isSignedOut(forAccountKeychainId: keychainId) {
            deleteCredential(forKeychainId: keychainId)
        }

        do {
            try appDatabase.deleteAccountSync(keychainId: keychainId)
        } catch {
            logger.error("removeAccount failed to delete account row: \(error.localizedDescription, privacy: .public)")
        }

        // Only re-point the default when the removed account was the active one,
        // so deleting a non-active account leaves the current selection intact.
        // The app is never left without a default: there's a fallback, or we
        // recreate the signed-out account for the same instance.
        guard wasDefault else { return }
        if let fallbackKeychainId {
            setDefaultAccount(forAccountKeychainId: fallbackKeychainId)
        } else if let instanceActorId, let instance = InstanceActorId(from: instanceActorId) {
            signInAsSignedOut(atInstance: instance)
        }
    }
}

// MARK: Credential read/write

extension AccountService {
    private func writeCredential(_ credential: LemmyCredential, forKeychainId keychainId: String) {
        credentialStore.setCredential(credential, forKeychainId: keychainId)
    }

    private func deleteCredential(forKeychainId keychainId: String) {
        credentialStore.removeCredential(forKeychainId: keychainId)
    }

    private func readCredential(forKeychainId keychainId: String) -> LemmyCredential? {
        credentialStore.credential(forKeychainId: keychainId)
    }
}

// MARK: - CredentialStore

/// Persists per-account `LemmyCredential`s. Production stores them in the
/// shared-group keychain (so the widget and extensions can read them); tests
/// inject an in-memory store to exercise the sign-in flow without the keychain
/// entitlements the test bundle lacks.
protocol CredentialStore: Sendable {
    func credential(forKeychainId keychainId: String) -> LemmyCredential?
    func setCredential(_ credential: LemmyCredential, forKeychainId keychainId: String)
    func removeCredential(forKeychainId keychainId: String)
}

/// Production `CredentialStore` backed by the shared-group keychain.
struct KeychainCredentialStore: CredentialStore {
    private static let keychainCredentialService = "J8B76VBZ57.info.ddenis.Spud.shared"

    /// The Keychain Shared Access Group where we store credentials.
    /// This is used to allow WidgetExtension to access the credentials e.g. for fetching top posts from users' subscription.
    private static let keychainSharedGroup = "group.info.ddenis.Spud.shared"

    private var keychain: Keychain {
        Keychain(
            service: Self.keychainCredentialService,
            accessGroup: Self.keychainSharedGroup
        )
    }

    func setCredential(_ credential: LemmyCredential, forKeychainId keychainId: String) {
        let stringValue = credential.toString()
        do {
            try keychain.set(stringValue, key: keychainId)
            logger.debug("Saved credential into keychain")
        } catch {
            logger.error("Failed to save credential into keychain: \(error.localizedDescription, privacy: .public)")
        }
    }

    func removeCredential(forKeychainId keychainId: String) {
        do {
            try keychain.remove(keychainId)
            logger.debug("Removed credential from keychain")
        } catch {
            logger.error("Failed to remove credential from keychain: \(error.localizedDescription, privacy: .public)")
        }
    }

    func credential(forKeychainId keychainId: String) -> LemmyCredential? {
        do {
            guard let stringValue = try keychain.get(keychainId) else {
                logger.debug("Did not find credential in keychain")
                return nil
            }

            do {
                let credential = try LemmyCredential.fromString(stringValue)
                logger.debug("Fetched credential from keychain")
                return credential
            } catch {
                logger.error("Failed to parse credential '\(stringValue, privacy: .sensitive)': \(error.localizedDescription, privacy: .public)")
                return nil
            }
        } catch {
            logger.assertionFailure("Failed to get credential from keychain: \(error.localizedDescription)")
            return nil
        }
    }
}
