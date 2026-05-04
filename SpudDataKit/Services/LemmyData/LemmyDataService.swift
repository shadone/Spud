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
    /// Creates feed with the explicitly given feed parameters. Used by the
    /// AccountServiceType.createFeed(...) wrappers; not called by view code.
    func createFeed(_ type: FeedType) -> LemmyFeed

    /// Returns the account's preferred default listing type.
    func defaultListingType() -> Components.Schemas.ListingType

    /// Returns the account's preferred default sort type.
    func defaultSortType() -> Components.Schemas.SortType

    func getOrCreate(postId: Components.Schemas.PostID) -> LemmyPost

    func getOrCreate(personId: Components.Schemas.PersonID) -> LemmyPerson
}

@MainActor
public class LemmyDataService: LemmyDataServiceType {
    // MARK: Public

    let accountObjectId: NSManagedObjectID
    @Atomic var accountIdentifierForLogging: String

    // MARK: Private

    private let dataStore: DataStoreType

    private var mainContext: NSManagedObjectContext {
        dataStore.mainContext
    }

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

    public func createFeed(_ type: FeedType) -> LemmyFeed {
        assert(Thread.current.isMainThread)

        let accountInMainContext = dataStore.mainContext
            .object(with: accountObjectId) as! LemmyAccount

        let newFeed = LemmyFeed(
            type,
            account: accountInMainContext,
            in: dataStore.mainContext
        )

        dataStore.saveIfNeeded()

        return newFeed
    }

    public func getOrCreate(postId: Components.Schemas.PostID) -> LemmyPost {
        assert(Thread.current.isMainThread)

        let mainContext = dataStore.mainContext
        let accountInMainContext = mainContext
            .object(with: accountObjectId) as! LemmyAccount

        let request = LemmyPost.fetchRequest(postId: postId, account: accountInMainContext)
        do {
            let results = try mainContext.fetch(request)
            if results.isEmpty {
                let newPost = LemmyPost(
                    postId: postId,
                    account: accountInMainContext,
                    in: mainContext
                )
                dataStore.saveIfNeeded()
                return newPost
            } else {
                logger.assert(results.count == 1, "Found \(results.count) posts with id '\(postId)'")
                return results[0]
            }
        } catch {
            logger.fault("Failed to fetch a post: \(error, privacy: .public)")
            fatalError("Failed to fetch a post: \(error)")
        }
    }

    public func getOrCreate(personId: Components.Schemas.PersonID) -> LemmyPerson {
        assert(Thread.current.isMainThread)

        let mainContext = dataStore.mainContext
        let accountInMainContext = mainContext
            .object(with: accountObjectId) as! LemmyAccount

        let request = LemmyPerson.fetchRequest(
            personId: personId,
            site: accountInMainContext.site
        )

        do {
            let results = try mainContext.fetch(request)
            if results.isEmpty {
                let newPerson = LemmyPerson(
                    personId: personId,
                    site: accountInMainContext.site,
                    in: mainContext
                )
                dataStore.saveIfNeeded()
                return newPerson
            } else {
                logger.assert(results.count == 1, "Found \(results.count) persons with id '\(personId)'")
                return results[0]
            }
        } catch {
            logger.fault("Failed to fetch a person: \(error, privacy: .public)")
            fatalError("Failed to fetch a person: \(error)")
        }
    }
}
