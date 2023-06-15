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
    func accountForSignedOut(instanceUrl: URL) -> LemmyAccount

    /// Returns a LemmyService instance used for talking to Reddit api.
    /// - Parameter account: which account to act as.
    func lemmyService(for account: LemmyAccount) -> LemmyServiceType
}

protocol HasAccountService {
    var accountService: AccountServiceType { get }
}

class AccountService: AccountServiceType {
    // MARK: Private

    private let lemmyDataStore: LemmyDataStoreType

    private var signedOutAccountObjectId: NSManagedObjectID?
    private var lemmyServices: [NSManagedObjectID: LemmyService] = [:]

    // MARK: Functions

    init(
        lemmyDataStore: LemmyDataStoreType
    ) {
        self.lemmyDataStore = lemmyDataStore
    }

    func accountForSignedOut(instanceUrl: URL) -> LemmyAccount {
        let account: LemmyAccount? = {
            let request: NSFetchRequest<LemmyAccount> = LemmyAccount.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(
                format: "isSignedOutAccountType == true AND instanceUrl == %@",
                instanceUrl.absoluteString
            )
            do {
                let accounts = try lemmyDataStore.mainContext.fetch(request)
                if accounts.count > 1 {
                    os_log("Expected zero or one but found %{public}d signed out accounts instead!",
                           log: .accountService, type: .error,
                           accounts.count)
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
            let account = LemmyAccount(context: lemmyDataStore.mainContext)
            account.instanceUrl = instanceUrl
            account.isSignedOutAccountType = true
            account.createdAt = Date()
            account.updatedAt = account.createdAt
            lemmyDataStore.saveIfNeeded()
            return account
        }

        return account ?? createAccountForSignedOut()
    }

    func lemmyService(for account: LemmyAccount) -> LemmyServiceType {
        let accountObjectId = account.objectID

        if let redditService = lemmyServices[accountObjectId] {
            return redditService
        }

        let api = LemmyApi(instanceUrl: account.instanceUrl)

        let lemmyService = LemmyService(
            accountObjectId: accountObjectId,
            lemmyDataStore: lemmyDataStore,
            lemmyApi: api
        )
        lemmyServices[accountObjectId] = lemmyService

        return lemmyService
    }}
