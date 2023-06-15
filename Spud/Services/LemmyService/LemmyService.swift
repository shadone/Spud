//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import os.log
import LemmyKit

protocol LemmyServiceType {
    func createFeed(_ type: LemmyFeed.FeedType) -> LemmyFeed

    func fetchFeed(
        feedId: NSManagedObjectID,
        page pageNumber: Int?
    ) async throws
}

class LemmyService: LemmyServiceType {
    // MARK: Public

    let accountObjectId: NSManagedObjectID

    // MARK: Private

    private let lemmyDataStore: LemmyDataStoreType
    private let lemmyApi: LemmyApi

    private var mainContext: NSManagedObjectContext {
        lemmyDataStore.mainContext
    }

    private lazy var backgroundContext: NSManagedObjectContext = {
        let backgroundContext = lemmyDataStore.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
        return backgroundContext
    }()

    // MARK: Functions

    init(
        accountObjectId: NSManagedObjectID,
        lemmyDataStore: LemmyDataStoreType,
        lemmyApi: LemmyApi
    ) {
        self.accountObjectId = accountObjectId
        self.lemmyDataStore = lemmyDataStore
        self.lemmyApi = lemmyApi
    }

    private func object<CoreDataObject>(
        with objectId: NSManagedObjectID,
        type _: CoreDataObject.Type
    ) async -> CoreDataObject {
        await backgroundContext.perform {
            self.backgroundContext.object(with: objectId) as! CoreDataObject
        }
    }

    private func saveIfNeeded() {
        backgroundContext.performAndWait {
            guard backgroundContext.hasChanges else { return }

            do {
                try backgroundContext.save()
            } catch {
                os_log("Failed to save context: %{public}@",
                       log: .lemmyService, type: .error,
                       String(describing: error))
            }
        }
    }

    func createFeed(_ type: LemmyFeed.FeedType) -> LemmyFeed {
        let accountInMainContext = lemmyDataStore.mainContext
            .object(with: accountObjectId) as! LemmyAccount

        let newFeed = LemmyFeed(
            type,
            account: accountInMainContext,
            in: lemmyDataStore.mainContext
        )

        lemmyDataStore.saveIfNeeded()

        return newFeed
    }

    func fetchFeed(
        feedId: NSManagedObjectID,
        page pageNumber: Int?
    ) async throws {
        let feed = await object(with: feedId, type: LemmyFeed.self)

        switch feed.feedType {
        case let .frontpage(listingType, sortType):
            let response = try await lemmyApi.getPosts(
                type: listingType,
                sort: sortType,
                page: pageNumber
            )

            feed.append(contentsOf: response.posts)

            saveIfNeeded()
        }
    }
}
