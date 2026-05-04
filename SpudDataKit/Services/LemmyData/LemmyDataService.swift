//
// Copyright (c) 2024, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import LemmyKit
import OSLog
import SpudUtilKit

private let logger = Logger.lemmyDataService

@MainActor
public protocol LemmyDataServiceType {
    /// Returns the account's preferred default listing type.
    func defaultListingType() -> Components.Schemas.ListingType

    /// Returns the account's preferred default sort type.
    func defaultSortType() -> Components.Schemas.SortType
}

@MainActor
public class LemmyDataService: LemmyDataServiceType {
    // MARK: Public

    let accountObjectId: NSManagedObjectID
    @Atomic var accountIdentifierForLogging: String

    // MARK: Private

    private let dataStore: DataStoreType

    /// Returns account object in **main context**.
    private var accountInMainContext: LemmyAccount {
        dataStore.mainContext.object(with: accountObjectId) as! LemmyAccount
    }

    // MARK: Functions

    init(
        account: LemmyAccount,
        dataStore: DataStoreType
    ) {
        accountObjectId = account.objectID
        accountIdentifierForLogging = account.identifierForLogging

        self.dataStore = dataStore

        logger.info("Creating new service for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))")
    }

    public func defaultListingType() -> Components.Schemas.ListingType {
        lazy var siteListingType = accountInMainContext.site.siteInfo?.defaultPostListingType
        let userListingType = accountInMainContext.accountInfo?.defaultListingType
        return userListingType ?? siteListingType ?? .All
    }

    public func defaultSortType() -> Components.Schemas.SortType {
        let userSortType = accountInMainContext.accountInfo?.defaultSortType
        return userSortType ?? .Hot
    }
}
