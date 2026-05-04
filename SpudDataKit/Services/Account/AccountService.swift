//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import KeychainAccess
import LemmyKit
import OSLog
import SpudUtilKit

private let logger = Logger.accountService

@MainActor
public protocol AccountServiceType: AnyObject {
    /// Returns an account that represents a signed out user on a given Lemmy instance.
    func accountForSignedOut(
        at site: LemmySite,
        isServiceAccount: Bool,
        in context: NSManagedObjectContext
    ) -> LemmyAccount

    /// Creates (if needed) the signed-out account for `site` and marks it as the default account.
    /// Stage 7 cutover entry point used by `LoginViewController` so call sites do not need to
    /// resolve a `LemmyAccount` or pass a managed object context.
    func signInAsSignedOut(at site: LemmySite)

    /// Looks up a most suitable account for the the given Lemmy instance.
    ///
    /// - Note: This is meant to be used only for real user actions, not for service accounts.
    ///
    /// - Returns: A detault account if it is on the same site, if exists. Otherwise returns a signed out account.
    func account(
        at site: LemmySite,
        in context: NSManagedObjectContext
    ) -> LemmyAccount

    /// Looks up the LemmyAccount whose keychain id matches `keychainId`.
    /// Used by Stage 5 cutover screens to bridge from a GRDB-backed
    /// `accountKeychainId` back to the legacy NSManagedObject when the
    /// receiver still expects one (e.g. `setDefaultAccount`).
    func account(withKeychainId keychainId: String, in context: NSManagedObjectContext) -> LemmyAccount?

    /// Returns all signed out accounts. The returned accounts are fetched in the specified context.
    func allSignedOut(in context: NSManagedObjectContext) -> [LemmyAccount]

    /// Returns a list of all accounts.
    func allAccounts(
        includeSignedOutAccount: Bool,
        in context: NSManagedObjectContext
    ) -> [LemmyAccount]

    /// Log in to a given Lemmy instance with explicitly provided username and password.
    func login(
        site: LemmySite,
        username: String,
        password: String
    ) async throws -> LemmyAccount

    /// Returns an account that is shown on app launch.
    func defaultAccount() -> LemmyAccount

    /// Chooses which account is "default" i.e. used automatically at app launch.
    func setDefaultAccount(_ account: LemmyAccount)

    /// Resolves the account by `keychainId` and marks it default. No-op if
    /// the account isn't registered.
    func setDefaultAccount(forAccountKeychainId keychainId: String)

    /// Resolves an account suitable for `instance` and returns its
    /// `accountKeychainId`. Creates the site and a signed-out account if
    /// none exist. Stage 7 cutover entry point for `AppCoordinator.open`,
    /// so the caller does not need to touch `LemmyAccount`,
    /// `siteService`, or `NSManagedObjectContext`.
    func accountKeychainId(forInstance instance: InstanceActorId) -> String

    /// Returns a LemmyDataService instance for managing CoreData types.
    /// This is isolated to the main actor.
    func lemmyDataService(for account: LemmyAccount) -> LemmyDataServiceType

    /// Resolves the LemmyDataService for the account whose
    /// `accountKeychainId` matches `keychainId`. Crashes if no such account
    /// is registered.
    func lemmyDataService(forAccountKeychainId keychainId: String) -> LemmyDataServiceType

    /// Returns a LemmyService instance used for talking to Lemmy api.
    /// - Parameter account: which account to act as.
    func lemmyService(for account: LemmyAccount) -> LemmyServiceType

    /// Resolves the LemmyService for the account whose `accountKeychainId`
    /// matches `keychainId`. Crashes if no such account is registered.
    func lemmyService(forAccountKeychainId keychainId: String) -> LemmyServiceType
}

@MainActor
public extension AccountServiceType {
    /// Creates a feed for `account` with the given parameters. Returns a
    /// `FeedHandle` carrying the stable `feedKey` (for GRDB observations and
    /// LemmyService.fetchFeed) and the `feedType` (for navigation/sort UI).
    func createFeed(
        for account: LemmyAccount,
        feedType: FeedType,
        identifierForDebugging: String? = nil
    ) -> FeedHandle {
        let feed = lemmyDataService(for: account).createFeed(feedType)
        if let identifierForDebugging {
            feed.identifierForDebugging = identifierForDebugging
        }
        return FeedHandle(feedKey: feed.id, feedType: feed.feedType)
    }

    /// Creates a feed for `account` using the account's default listing and
    /// sort types. Used by the split view's primary post list.
    func createDefaultFeed(for account: LemmyAccount) -> FeedHandle {
        let dataService = lemmyDataService(for: account)
        let feedType = FeedType.frontpage(
            listingType: dataService.defaultListingType(),
            sortType: dataService.defaultSortType()
        )
        let feed = dataService.createFeed(feedType)
        return FeedHandle(feedKey: feed.id, feedType: feed.feedType)
    }

    /// Creates a feed for `account` derived from `existing` (same feed type
    /// shape) but with `sortType` overridden when non-nil. Used by
    /// PostListViewModel.didChangeSortType / didClickReload.
    func createFeed(
        duplicateOf existing: FeedHandle,
        for account: LemmyAccount,
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
            }
        }()
        let feed = lemmyDataService(for: account).createFeed(newFeedType)
        return FeedHandle(feedKey: feed.id, feedType: feed.feedType)
    }

    // keychainId-keyed counterparts. Stage 7 cutover screens that have
    // already moved off `LemmyAccount` use these to talk to the legacy
    // LemmyDataService without re-resolving the managed object.

    func createFeed(
        forAccountKeychainId keychainId: String,
        feedType: FeedType,
        identifierForDebugging: String? = nil
    ) -> FeedHandle {
        let feed = lemmyDataService(forAccountKeychainId: keychainId).createFeed(feedType)
        if let identifierForDebugging {
            feed.identifierForDebugging = identifierForDebugging
        }
        return FeedHandle(feedKey: feed.id, feedType: feed.feedType)
    }

    func createDefaultFeed(forAccountKeychainId keychainId: String) -> FeedHandle {
        let dataService = lemmyDataService(forAccountKeychainId: keychainId)
        let feedType = FeedType.frontpage(
            listingType: dataService.defaultListingType(),
            sortType: dataService.defaultSortType()
        )
        let feed = dataService.createFeed(feedType)
        return FeedHandle(feedKey: feed.id, feedType: feed.feedType)
    }

    func createFeed(
        duplicateOf existing: FeedHandle,
        forAccountKeychainId keychainId: String,
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
            }
        }()
        let feed = lemmyDataService(forAccountKeychainId: keychainId).createFeed(newFeedType)
        return FeedHandle(feedKey: feed.id, feedType: feed.feedType)
    }
}

@MainActor
public protocol HasAccountService {
    var accountService: AccountServiceType { get }
}

@MainActor
public class AccountService: AccountServiceType {
    // MARK: Private

    private let dataStore: DataStoreType
    private let appDatabase: AppDatabase
    private let siteService: SiteServiceType

    private var lemmyServices: [NSManagedObjectID: LemmyService] = [:]
    private var lemmyDataServices: [NSManagedObjectID: LemmyDataService] = [:]

    // MARK: Functions

    public init(
        siteService: SiteServiceType,
        dataStore: DataStoreType,
        appDatabase: AppDatabase
    ) {
        self.dataStore = dataStore
        self.appDatabase = appDatabase
        self.siteService = siteService
    }

    /// Fire-and-forget mirror of a freshly created Core Data account into
    /// AppDatabase. Snapshots the relevant fields synchronously on the main
    /// actor before hopping off so the Task does not touch the managed
    /// object across actor boundaries. Failures are logged; the legacy
    /// Core Data path remains the source of truth until 3d.
    private func mirrorAccount(_ account: LemmyAccount) {
        let actorId = account.site.instance.actorId
        let keychainId = account.id
        let isSignedOut = account.isSignedOutAccountType
        let isServiceAccount = account.isServiceAccount
        Task { [appDatabase] in
            do {
                let (_, siteId) = try await appDatabase.ensureSite(forInstance: actorId)
                _ = try await appDatabase.ensureAccount(
                    keychainId: keychainId,
                    siteId: siteId,
                    isSignedOut: isSignedOut,
                    isServiceAccount: isServiceAccount
                )
            } catch {
                logger.error("""
                    Failed to mirror account to AppDatabase: \
                    \(String(describing: error), privacy: .public)
                    """)
            }
        }
    }

    public func accountForSignedOut(
        at site: LemmySite,
        isServiceAccount: Bool,
        in context: NSManagedObjectContext
    ) -> LemmyAccount {
        assert(Thread.current.isMainThread)

        let account: LemmyAccount? = {
            let request: NSFetchRequest<LemmyAccount> = LemmyAccount.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(
                format: "isSignedOutAccountType == true AND isServiceAccount == %@ AND site == %@",
                NSNumber(booleanLiteral: isServiceAccount),
                site
            )
            do {
                let accounts = try context.fetch(request)
                logger.assert(accounts.count <= 1, """
                    Expected zero or one but found \(accounts.count) \
                    signed out accounts for \(site.identifierForLogging)!
                    """)
                return accounts.first
            } catch {
                logger.assertionFailure("""
                    Failed to fetch account for \(site.identifierForLogging): \
                    \(error.localizedDescription)
                    """)
                return nil
            }
        }()

        func createAccountForSignedOut() -> LemmyAccount {
            let account = LemmyAccount(signedOutAt: site, in: context)
            account.isServiceAccount = isServiceAccount
            context.saveIfNeeded()
            mirrorAccount(account)
            return account
        }

        return account ?? createAccountForSignedOut()
    }

    public func account(
        withKeychainId keychainId: String,
        in context: NSManagedObjectContext
    ) -> LemmyAccount? {
        assert(Thread.current.isMainThread)
        let request: NSFetchRequest<LemmyAccount> = LemmyAccount.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", keychainId)
        do {
            return try context.fetch(request).first
        } catch {
            logger.assertionFailure("Failed to fetch account by keychainId: \(error.localizedDescription)")
            return nil
        }
    }

    public func allSignedOut(in context: NSManagedObjectContext) -> [LemmyAccount] {
        assert(Thread.current.isMainThread)

        let request: NSFetchRequest<LemmyAccount> = LemmyAccount.fetchRequest()
        request.predicate = NSPredicate(
            format: "isSignedOutAccountType == true"
        )
        do {
            return try context.fetch(request)
        } catch {
            logger.assertionFailure("Failed to fetch all signed out accounts: \(error.localizedDescription)")
            return []
        }
    }

    public func allAccounts(
        includeSignedOutAccount: Bool,
        in context: NSManagedObjectContext
    ) -> [LemmyAccount] {
        assert(Thread.current.isMainThread)

        let request: NSFetchRequest<LemmyAccount> = LemmyAccount.fetchRequest()
        if !includeSignedOutAccount {
            request.predicate = NSPredicate(
                format: "isSignedOutAccountType == false"
            )
        }
        do {
            return try context.fetch(request)
        } catch {
            logger.assertionFailure("Failed to fetch all accounts: \(error.localizedDescription)")
            return []
        }
    }

    public func defaultAccount() -> LemmyAccount {
        assert(Thread.current.isMainThread)

        let request: NSFetchRequest<LemmyAccount> = LemmyAccount.fetchRequest()
        // We intentionally do not set predicate here.
        // In case there is a problem with the data and we somehow lost the default account,
        // we would pick the next available account to make the default one.
        request.predicate = NSPredicate(
            format: "isServiceAccount == false"
        )
        request.fetchLimit = 1
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LemmyAccount.isDefaultAccount, ascending: false),
            NSSortDescriptor(keyPath: \LemmyAccount.id, ascending: true),
        ]

        let accounts: [LemmyAccount]
        do {
            accounts = try dataStore.mainContext.fetch(request)
        } catch {
            logger.fault("Failed to fetch default account: \(error.localizedDescription, privacy: .public)")
            fatalError("Failed to fetch default account: \(error.localizedDescription)")
        }

        if let account = accounts.first {
            if !account.isDefaultAccount {
                setDefaultAccount(account)
            }
            return account
        }

        // we do not have a usable account, this is likely first app launch,
        // lets create a new account.
        return createDefaultAccount()
    }

    private func createDefaultAccount() -> LemmyAccount {
        // TODO: add separate call siteService.siteForDefaultAccount
        let site = siteService.allSites(in: dataStore.mainContext).first!
        let account = LemmyAccount(signedOutAt: site, in: dataStore.mainContext)
        dataStore.saveIfNeeded()
        mirrorAccount(account)
        return account
    }

    public func setDefaultAccount(_ accountToMakeDefault: LemmyAccount) {
        assert(!accountToMakeDefault.isServiceAccount)
        assert(Thread.current.isMainThread)

        logger.info("Setting default account \(accountToMakeDefault.identifierForLogging, privacy: .public)")

        for account in allAccounts(includeSignedOutAccount: true, in: dataStore.mainContext) {
            account.isDefaultAccount = false
        }

        accountToMakeDefault.isDefaultAccount = true

        dataStore.saveIfNeeded()

        let defaultKeychainId = accountToMakeDefault.identifierForLogging
        Task { [appDatabase] in
            do {
                try await appDatabase.setDefaultAccount(keychainId: defaultKeychainId)
            } catch {
                logger.error("Failed to mirror default-account flag to AppDatabase: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func api(for site: LemmySite, credential: LemmyCredential?) -> LemmyApi {
        guard let instanceUrl = site.instance.actorId.url else {
            fatalError("Failed to create URL from instance actor id '\(site.instance.actorId)'")
        }
        return LemmyApi(instanceUrl: instanceUrl, credential: credential)
    }

    public func lemmyDataService(for account: LemmyAccount) -> LemmyDataServiceType {
        assert(Thread.current.isMainThread)

        let accountObjectId = account.objectID

        if let lemmyDataService = lemmyDataServices[accountObjectId] {
            logger.debug("Returning existing LemmyDataService for \(account.identifierForLogging)")
            return lemmyDataService
        }

        logger.debug("Creating new LemmyDataService for \(account.identifierForLogging, privacy: .public)")

        let lemmyDataService = LemmyDataService(
            account: account,
            dataStore: dataStore
        )
        lemmyDataServices[accountObjectId] = lemmyDataService

        return lemmyDataService
    }

    public func lemmyService(for account: LemmyAccount) -> LemmyServiceType {
        assert(Thread.current.isMainThread)

        let accountObjectId = account.objectID

        if let lemmyService = lemmyServices[accountObjectId] {
            logger.debug("Returning existing LemmyService for \(account.identifierForLogging)")
            return lemmyService
        }

        let credential = readCredential(for: account)
        let api = api(for: account.site, credential: credential)

        logger.debug("Creating new LemmyService for \(account.identifierForLogging, privacy: .public)")

        let lemmyService = LemmyService(
            account: account,
            dataStore: dataStore,
            appDatabase: appDatabase,
            api: api
        )
        lemmyServices[accountObjectId] = lemmyService

        return lemmyService
    }

    public func signInAsSignedOut(at site: LemmySite) {
        let account = accountForSignedOut(
            at: site,
            isServiceAccount: false,
            in: dataStore.mainContext
        )
        setDefaultAccount(account)
    }

    public func setDefaultAccount(forAccountKeychainId keychainId: String) {
        guard let account = account(withKeychainId: keychainId, in: dataStore.mainContext) else {
            logger.error("Cannot setDefaultAccount: no account for keychainId")
            return
        }
        setDefaultAccount(account)
    }

    public func accountKeychainId(forInstance instance: InstanceActorId) -> String {
        assert(Thread.current.isMainThread)
        let mainContext = dataStore.mainContext
        let site = siteService.site(for: instance, in: mainContext)
        return account(at: site, in: mainContext).id
    }

    public func lemmyDataService(forAccountKeychainId keychainId: String) -> LemmyDataServiceType {
        guard let account = account(withKeychainId: keychainId, in: dataStore.mainContext) else {
            fatalError("No account registered for keychainId \(keychainId)")
        }
        return lemmyDataService(for: account)
    }

    public func lemmyService(forAccountKeychainId keychainId: String) -> LemmyServiceType {
        guard let account = account(withKeychainId: keychainId, in: dataStore.mainContext) else {
            fatalError("No account registered for keychainId \(keychainId)")
        }
        return lemmyService(for: account)
    }

    public func login(
        site: LemmySite,
        username: String,
        password: String
    ) async throws -> LemmyAccount {
        // Creating temporary authenticated LemmyApi object for making login request.
        let api = api(for: site, credential: nil)

        let response: Components.Schemas.LoginResponse
        do {
            response = try await api.login(username: username, password: password)
        } catch {
            let error = AccountServiceLoginError(from: error)

            if case .invalidLogin = error {
                // this is a "good" kind of error, no need to log this
                throw error
            }

            logger.error("""
                Login failed. site=\(site.identifierForLogging, privacy: .public). \
                username=\(username, privacy: .sensitive(mask: .hash))
                \(String(describing: error), privacy: .public)
                """)
            throw error
        }

        guard let jwt = response.jwt else {
            throw AccountServiceLoginError.missingJwt
        }
        let credential = LemmyCredential(jwt: jwt)

        // TODO: use "sub" from JWT instead of username here.
        // using username here is wrong, it is not a stable identifier,
        // it can be changed without invalidating the account.
        // We should use "sub" claim from JWT.
        let account = LemmyAccount(
            userId: username,
            at: site,
            in: dataStore.mainContext
        )

        setDefaultAccount(account)
        dataStore.saveIfNeeded()

        writeCredential(credential, for: account)
        mirrorAccount(account)

        return account
    }

    public func account(
        at site: LemmySite,
        in context: NSManagedObjectContext
    ) -> LemmyAccount {
        assert(Thread.current.isMainThread)

        let request: NSFetchRequest<LemmyAccount> = LemmyAccount.fetchRequest()
        request.predicate = NSPredicate(
            format: "site == %@",
            site
        )

        let accounts: [LemmyAccount]
        do {
            accounts = try context.fetch(request)
        } catch {
            logger.error("Failed to fetch accounts for site: \(error.localizedDescription, privacy: .public)")
            fatalError("Failed to fetch accounts for site: \(error.localizedDescription)")
        }

        if let defaultAccount = accounts.first(where: { $0.isDefaultAccount }) {
            return defaultAccount
        }

        if let signedOutAccount = accounts.first(where: { $0.isSignedOutAccountType }) {
            // Return the first signed out account. It might be a service account.
            return signedOutAccount
        }

        // TODO: check if there a signed in account for that site
        // It might be interesting to return both new signed out account and the existing
        // account. This way we could show UI like "here is the data from the source
        // but fyi you have an account there".

        func createAccountForSignedOut() -> LemmyAccount {
            let account = LemmyAccount(signedOutAt: site, in: context)
            account.isServiceAccount = false
            context.saveIfNeeded()
            mirrorAccount(account)
            return account
        }

        return createAccountForSignedOut()
    }
}

// MARK: Credential read/write

extension AccountService {
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

    private func writeCredential(_ credential: LemmyCredential, for account: LemmyAccount) {
        assert(!account.objectID.isTemporaryID)
        let key = account.objectID.uriRepresentation().absoluteString

        let stringValue = credential.toString()

        do {
            try keychain.set(stringValue, key: key)
            logger.debug("Saved credential into keychain")
        } catch {
            logger.error("Failed to save credential into keychain: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func readCredential(for account: LemmyAccount) -> LemmyCredential? {
        assert(!account.objectID.isTemporaryID)
        guard !account.isSignedOutAccountType else { return nil }

        do {
            let key = account.objectID.uriRepresentation().absoluteString
            guard let stringValue = try keychain.get(key) else {
                logger.debug("Did not find credential in keychain")
                return nil
            }

            let credential: LemmyCredential
            do {
                credential = try LemmyCredential.fromString(stringValue)
            } catch {
                logger.error("Failed to parse credential '\(stringValue, privacy: .sensitive)': \(error.localizedDescription, privacy: .public)")
                return nil
            }

            logger.debug("Fetched credential from keychain")

            return credential
        } catch {
            logger.assertionFailure("Failed to get credential from keychain: \(error.localizedDescription)")
            return nil
        }
    }
}
