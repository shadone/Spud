//
// Copyright (c) 2024, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import LemmyKit
import OSLog
import SpudUtilKit

private let logger = Logger.lemmyDataService

@MainActor
public protocol LemmyDataServiceType {
    /// Creates feed with default parameters for the account.
    func createFeed() -> LemmyFeed

    /// Creates feed for the given ``listingType`` with default sort type parameters for the account.
    func createFeed(listingType: Components.Schemas.ListingType) -> LemmyFeed

    /// Creates feed with the explicitly given feed parameters.
    func createFeed(_ type: FeedType) -> LemmyFeed

    func createFeed(duplicateOf feed: LemmyFeed) -> LemmyFeed

    func createFeed(
        duplicateOf feed: LemmyFeed,
        sortType: Components.Schemas.SortType?
    ) -> LemmyFeed

    func getOrCreate(postId: Components.Schemas.PostID) -> LemmyPost

    func getOrCreate(personId: Components.Schemas.PersonID) -> LemmyPerson
}

public extension LemmyDataServiceType {
    func createFeed(duplicateOf feed: LemmyFeed) -> LemmyFeed {
        createFeed(duplicateOf: feed, sortType: nil)
    }
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

    private func defaultListingType(
        for account: LemmyAccount
    ) -> Components.Schemas.ListingType {
        lazy var siteListingType = accountInMainContext.site.siteInfo?.defaultPostListingType
        let userListingType = accountInMainContext.accountInfo?.defaultListingType
        return userListingType ?? siteListingType ?? .All
    }

    private func defaultSortType(
        for account: LemmyAccount
    ) -> Components.Schemas.SortType {
        let userSortType = accountInMainContext.accountInfo?.defaultSortType
        return userSortType ?? .Hot
    }

    public func createFeed() -> LemmyFeed {
        assert(Thread.current.isMainThread)

        let accountInMainContext = accountInMainContext

        let listingType = defaultListingType(for: accountInMainContext)
        let sortType = defaultSortType(for: accountInMainContext)

        let newFeed = LemmyFeed(
            .frontpage(listingType: listingType, sortType: sortType),
            account: accountInMainContext,
            in: dataStore.mainContext
        )

        dataStore.saveIfNeeded()

        return newFeed
    }

    public func createFeed(
        listingType: Components.Schemas.ListingType
    ) -> LemmyFeed {
        assert(Thread.current.isMainThread)

        let accountInMainContext = accountInMainContext

        let sortType = defaultSortType(for: accountInMainContext)

        let newFeed = LemmyFeed(
            .frontpage(listingType: listingType, sortType: sortType),
            account: accountInMainContext,
            in: dataStore.mainContext
        )

        dataStore.saveIfNeeded()

        return newFeed
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

    public func createFeed(
        duplicateOf feed: LemmyFeed,
        sortType: Components.Schemas.SortType?
    ) -> LemmyFeed {
        assert(Thread.current.isMainThread)

        let newFeed = LemmyFeed(
            duplicateOf: feed,
            sortType: sortType,
            in: mainContext
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
                let existingPost = results[0]
                return existingPost
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
                let existingPerson = results[0]
                return existingPerson
            }
        } catch {
            logger.fault("Failed to fetch a person: \(error, privacy: .public)")
            fatalError("Failed to fetch a person: \(error)")
        }
    }
}
