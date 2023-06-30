//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Combine
import Foundation
import os.log
import LemmyKit
import KeychainAccess

protocol AccountServiceType: AnyObject {
    /// Returns an account that represents a signed out user on a given Lemmy instance.
    func accountForSignedOut(
        at site: LemmySite,
        isServiceAccount: Bool,
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
    func defaultAccount() -> LemmyAccount?

    /// Chooses which account is "default" i.e. used automatically at app launch.
    func setDefaultAccount(_ account: LemmyAccount)

    /// Returns a LemmyService instance used for talking to Lemmy api.
    /// - Parameter account: which account to act as.
    func lemmyService(for account: LemmyAccount) -> LemmyServiceType
}

protocol HasAccountService {
    var accountService: AccountServiceType { get }
}

class AccountService: AccountServiceType {
    // MARK: Private

    private let dataStore: DataStoreType

    private var lemmyServices: [NSManagedObjectID: LemmyService] = [:]

    // MARK: Functions

    init(
        dataStore: DataStoreType
    ) {
        self.dataStore = dataStore
    }

    func accountForSignedOut(
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
                if accounts.count > 1 {
                    os_log("Expected zero or one but found %{public}d signed out accounts for %{public}@!",
                           log: .accountService, type: .error,
                           accounts.count, site.identifierForLogging)
                    assertionFailure()
                }
                return accounts.first
            } catch {
                os_log("Failed to fetch account for %{public}@: %{public}@",
                       log: .accountService, type: .error,
                       site.identifierForLogging,
                       error.localizedDescription)
                assertionFailure()
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

    func allSignedOut(in context: NSManagedObjectContext) -> [LemmyAccount] {
        assert(Thread.current.isMainThread)

        let request: NSFetchRequest<LemmyAccount> = LemmyAccount.fetchRequest()
        request.predicate = NSPredicate(
            format: "isSignedOutAccountType == true"
        )
        do {
            return try context.fetch(request)
        } catch {
            os_log("Failed to fetch all signed out accounts: %{public}@",
                   log: .accountService, type: .error,
                   error.localizedDescription)
            assertionFailure()
            return []
        }
    }

    func allAccounts(
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
            os_log("Failed to fetch all accounts: %{public}@",
                   log: .accountService, type: .error,
                   error.localizedDescription)
            assertionFailure()
            return []
        }
    }

    func defaultAccount() -> LemmyAccount? {
        assert(Thread.current.isMainThread)

        let request: NSFetchRequest<LemmyAccount> = LemmyAccount.fetchRequest()
        request.fetchLimit = 1
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LemmyAccount.isDefaultAccount, ascending: false),
            NSSortDescriptor(keyPath: \LemmyAccount.id, ascending: true),
        ]
        do {
            let accounts = try dataStore.mainContext.fetch(request)
            return accounts.first
        } catch {
            os_log("Failed to fetch default account: %{public}@",
                   log: .accountService, type: .error,
                   error.localizedDescription)
            assertionFailure()
            return nil
        }
    }

    func setDefaultAccount(_ accountToMakeDefault: LemmyAccount) {
        assert(!accountToMakeDefault.isServiceAccount)

        allAccounts(includeSignedOutAccount: true, in: dataStore.mainContext)
            .forEach {
                $0.isDefaultAccount = false
            }

        accountToMakeDefault.isDefaultAccount = true

        dataStore.saveIfNeeded()
    }

    private func api(for site: LemmySite) -> LemmyApi {
        guard let instanceUrl = URL(string: site.normalizedInstanceUrl) else {
            fatalError("Failed to create URL from normalized instance url '\(site.normalizedInstanceUrl)'")
        }
        return LemmyApi(instanceUrl: instanceUrl)
    }

    func lemmyService(for account: LemmyAccount) -> LemmyServiceType {
        assert(Thread.current.isMainThread)

        let accountObjectId = account.objectID

        if let lemmyService = lemmyServices[accountObjectId] {
            os_log("Returning existing LemmyService for %{public}@",
                   log: .accountService, type: .debug,
                   account.identifierForLogging)
            return lemmyService
        }

        let api = api(for: account.site)

        os_log("Creating new LemmyService for %{public}@",
               log: .accountService, type: .debug,
               account.identifierForLogging)

        // TODO: it would make for better architecture if auth / credential was part of LemmyApi
        // i.e. pass jwt to the `LemmyApi(auth: credential.jwt)` and let it add it to requests.
        let credential = readCredential(for: account)

        let lemmyService = LemmyService(
            account: account,
            credential: credential,
            dataStore: dataStore,
            api: api
        )
        lemmyServices[accountObjectId] = lemmyService

        return lemmyService
    }

    func login(
        site: LemmySite,
        username: String,
        password: String
    ) -> AnyPublisher<LemmyAccount, AccountServiceLoginError> {
        let api = api(for: site)
        return api.login(.init(username_or_email: username, password: password))
            .mapError { apiError -> AccountServiceLoginError in
                switch apiError {
                case let .serverError(error):
                    switch error {
                    case .value(.couldnt_find_that_username_or_email):
                        return .invalidUsernameOrEmail
                    case .value(.password_incorrect):
                        return .invalidPassword
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
}

// MARK: Credential read/write

extension AccountService {
    private static let keychainCredentialService = "info.ddenis.Spud.Accounts"

    private func writeCredential(_ credential: LemmyCredential, for account: LemmyAccount) {
        assert(!account.objectID.isTemporaryID)
        let key = account.objectID.uriRepresentation().absoluteString

        guard let stringValue = credential.toString() else {
            assertionFailure()
            return
        }

        let keychain = Keychain(service: Self.keychainCredentialService)
        do {
            try keychain.set(stringValue, key: key)
            os_log("Saved credential into keychain",
                   log: .accountService, type: .debug)
        } catch {
            os_log("Failed to save credential into keychain: %{public}@",
                   log: .accountService, type: .error,
                   error.localizedDescription)
        }
    }

    private func readCredential(for account: LemmyAccount) -> LemmyCredential? {
        assert(!account.objectID.isTemporaryID)
        guard !account.isSignedOutAccountType else { return nil }

        do {
            let keychain = Keychain(service: Self.keychainCredentialService)
            let key = account.objectID.uriRepresentation().absoluteString
            guard let stringValue = try keychain.get(key) else {
                os_log("Did not find credential in keychain",
                       log: .accountService, type: .debug)
                return nil
            }

            guard let credential = LemmyCredential.fromString(stringValue) else {
                assertionFailure()
                return nil
            }

            os_log("Fetched credential from keychain",
                   log: .accountService, type: .debug)

            return credential
        } catch {
            os_log("Failed to get credential from keychain: %{public}@",
                   log: .accountService, type: .error,
                   error.localizedDescription)
            assertionFailure(error.localizedDescription)
            return nil
        }
    }
}
