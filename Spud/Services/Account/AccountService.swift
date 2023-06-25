//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import os.log
import LemmyKit

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

    /// Returns an account that is shown on app launch.
    func defaultAccount() -> LemmyAccount?

    /// Chooses which account is "default" i.e. used automatically at app launch.
    func setDefaultAccount(_ account: LemmyAccount)

    /// Returns a LemmyService instance used for talking to Reddit api.
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

    func lemmyService(for account: LemmyAccount) -> LemmyServiceType {
        assert(Thread.current.isMainThread)

        let accountObjectId = account.objectID

        if let redditService = lemmyServices[accountObjectId] {
            return redditService
        }

        guard let instanceUrl = URL(string: account.site.normalizedInstanceUrl) else {
            fatalError("Failed to create URL from normalized instance url '\(account.site.normalizedInstanceUrl)'")
        }

        let api = LemmyApi(instanceUrl: instanceUrl)

        let lemmyService = LemmyService(
            account: account,
            dataStore: dataStore,
            api: api
        )
        lemmyServices[accountObjectId] = lemmyService

        return lemmyService
    }
}
