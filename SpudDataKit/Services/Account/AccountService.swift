//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import KeychainAccess
import LemmyKit
import OSLog
import SpudUtilKit

private let logger = Logger(.accountService)

public protocol AccountServiceType: AnyObject {
    /// Returns an account that represents a signed out user on a given Lemmy instance.
    func accountForSignedOut(
        at site: LemmySite,
        isServiceAccount: Bool,
        in context: NSManagedObjectContext
    ) -> LemmyAccount

    /// Looks up a most suitable account for the the given Lemmy instance.
    ///
    /// - Note: This is meant to be used only for real user actions, not for service accounts.
    ///
    /// - Returns: A detault account if it is on the same site, if exists. Otherwise returns a signed out account.
    func account(
        at site: LemmySite,
        in context: NSManagedObjectContext
    ) -> LemmyAccount

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
    ) -> AnyPublisher<LemmyAccount, AccountServiceLoginError>

    /// Returns an account that is shown on app launch.
    func defaultAccount() -> LemmyAccount

    /// Chooses which account is "default" i.e. used automatically at app launch.
    func setDefaultAccount(_ account: LemmyAccount)

    /// Returns a LemmyService instance used for talking to Lemmy api.
    /// - Parameter account: which account to act as.
    func lemmyService(for account: LemmyAccount) -> LemmyServiceType
}

public protocol HasAccountService {
    var accountService: AccountServiceType { get }
}

public class AccountService: AccountServiceType {
    // MARK: Private

    private let dataStore: DataStoreType
    private let siteService: SiteServiceType

    private var lemmyServices: [NSManagedObjectID: LemmyService] = [:]

    // MARK: Functions

    public init(
        siteService: SiteServiceType,
        dataStore: DataStoreType
    ) {
        self.dataStore = dataStore
        self.siteService = siteService
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
            return account
        }

        return account ?? createAccountForSignedOut()
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
        return account
    }

    public func setDefaultAccount(_ accountToMakeDefault: LemmyAccount) {
        assert(!accountToMakeDefault.isServiceAccount)
        assert(Thread.current.isMainThread)

        logger.info("Setting default account \(accountToMakeDefault.identifierForLogging, privacy: .public)")

        allAccounts(includeSignedOutAccount: true, in: dataStore.mainContext)
            .forEach {
                $0.isDefaultAccount = false
            }

        accountToMakeDefault.isDefaultAccount = true

        dataStore.saveIfNeeded()
    }

    private func api(for site: LemmySite, credential: LemmyCredential?) -> LemmyApi {
        guard let instanceUrl = site.instance.actorId.url else {
            fatalError("Failed to create URL from instance actor id '\(site.instance.actorId)'")
        }
        return LemmyApi(instanceUrl: instanceUrl, credential: credential)
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
            api: api
        )
        lemmyServices[accountObjectId] = lemmyService

        return lemmyService
    }

    public func login(
        site: LemmySite,
        username: String,
        password: String
    ) -> AnyPublisher<LemmyAccount, AccountServiceLoginError> {
        // Creating temporary authenticated LemmyApi object for making login request.
        let api = api(for: site, credential: nil)
        return api.login(.init(username_or_email: username, password: password))
            .mapError { apiError -> AccountServiceLoginError in
                switch apiError {
                case let .serverError(error):
                    switch error {
                    case .incorrect_login:
                        return .invalidLogin
                    default:
                        return .apiError(apiError)
                    }
                default:
                    return .apiError(apiError)
                }
            }
            .flatMap { response -> AnyPublisher<LemmyCredential, AccountServiceLoginError> in
                guard let jwt = response.jwt else {
                    return .fail(with: AccountServiceLoginError.missingJwt)
                }
                return .just(LemmyCredential(jwt: jwt))
            }
            .receive(on: DispatchQueue.main)
            .map { credential in
                // TODO: use "sub" from JWT instead of username here.
                // using username here is wrong, it is not a stable identifier,
                // it can be changed without invalidating the account.
                // We should use "sub" claim from JWT.
                let account = LemmyAccount(
                    userId: username,
                    at: site,
                    in: self.dataStore.mainContext
                )

                self.setDefaultAccount(account)
                self.dataStore.saveIfNeeded()

                self.writeCredential(credential, for: account)

                return account
            }
            .eraseToAnyPublisher()
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
