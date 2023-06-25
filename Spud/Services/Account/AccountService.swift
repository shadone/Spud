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
        in context: NSManagedObjectContext
    ) -> LemmyAccount

    /// Returns all signed out accounts. The returned accounts are fetched in the specified context.
    func allSignedOut(in context: NSManagedObjectContext) -> [LemmyAccount]

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
        in context: NSManagedObjectContext
    ) -> LemmyAccount {
        assert(Thread.current.isMainThread)

        let account: LemmyAccount? = {
            let request: NSFetchRequest<LemmyAccount> = LemmyAccount.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(
                format: "isSignedOutAccountType == true AND site == %@",
                site
            )
            do {
                let accounts = try context.fetch(request)
                if accounts.count > 1 {
                    os_log("Expected zero or one but found %{public}d signed out accounts instead! Site=%{public}@",
                           log: .accountService, type: .error,
                           accounts.count, site.normalizedInstanceUrl)
                    assertionFailure()
                }
                return accounts.first
            } catch {
                os_log("Failed to fetch account: %{public}@",
                       log: .accountService, type: .error,
                       error.localizedDescription)
                assertionFailure()
                return nil
            }
        }()

        func createAccountForSignedOut() -> LemmyAccount {
            let account = LemmyAccount(context: context)
            account.site = site
            account.isSignedOutAccountType = true
            account.createdAt = Date()
            account.updatedAt = account.createdAt
            dataStore.saveIfNeeded()
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
            accountObjectId: accountObjectId,
            dataStore: dataStore,
            api: api
        )
        lemmyServices[accountObjectId] = lemmyService

        return lemmyService
    }
}
