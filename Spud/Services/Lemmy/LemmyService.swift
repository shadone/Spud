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

    func createFeed(duplicateOf feed: LemmyFeed) -> LemmyFeed

    func createFeed(duplicateOf feed: LemmyFeed, sortType: SortType?) -> LemmyFeed

    func fetchFeed(
        feedId: NSManagedObjectID,
        page pageNumber: Int?
    ) -> AnyPublisher<Void, LemmyApiError>
}

extension LemmyServiceType {
    func createFeed(duplicateOf feed: LemmyFeed) -> LemmyFeed {
        createFeed(duplicateOf: feed, sortType: nil)
    }
}

class LemmyService: LemmyServiceType {
    // MARK: Public

    let accountObjectId: NSManagedObjectID

    // MARK: Private

    private let dataStore: DataStoreType
    private let api: LemmyApi

    private var mainContext: NSManagedObjectContext {
        dataStore.mainContext
    }

    private lazy var backgroundContext: NSManagedObjectContext = {
        let backgroundContext = dataStore.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
        return backgroundContext
    }()

    private lazy var backgroundScheduler: ManagedContextSchedulerOf<DispatchQueue> = {
        DispatchQueue.managedContentScheduler(backgroundContext)
    }()

    // MARK: Functions

    init(
        accountObjectId: NSManagedObjectID,
        dataStore: DataStoreType,
        api: LemmyApi
    ) {
        self.accountObjectId = accountObjectId
        self.dataStore = dataStore
        self.api = api
    }

    private func object<CoreDataObject>(
        with objectId: NSManagedObjectID,
        type _: CoreDataObject.Type
    ) async -> CoreDataObject {
        await backgroundContext.perform {
            self.backgroundContext.object(with: objectId) as! CoreDataObject
        }
    }

    private func object<CoreDataObject>(
        with objectId: NSManagedObjectID,
        type _: CoreDataObject.Type
    ) -> AnyPublisher<CoreDataObject, Never> {
        Future<CoreDataObject, Never> { promise in
            self.backgroundContext.perform {
                let object = self.backgroundContext.object(with: objectId) as! CoreDataObject
                promise(.success(object))
            }
        }
        .subscribe(on: backgroundScheduler)
        .eraseToAnyPublisher()
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

    func createFeed(
        duplicateOf feed: LemmyFeed,
        sortType: SortType?
    ) -> LemmyFeed {
        let newFeed = LemmyFeed(
            duplicateOf: feed,
            sortType: sortType,
            in: mainContext
        )

        dataStore.saveIfNeeded()

        return newFeed
    }

    func fetchFeed(
        feedId: NSManagedObjectID,
        page pageNumber: Int?
    ) -> AnyPublisher<Void, LemmyApiError> {
        object(with: feedId, type: LemmyFeed.self)
            .setFailureType(to: LemmyApiError.self)
            .flatMap { feed -> AnyPublisher<Void, LemmyApiError> in
                switch feed.feedType {
                case let .frontpage(listingType, sortType):
                    os_log("Fetch feed page %{public}@",
                           log: .lemmyService, type: .debug,
                           pageNumber.map { "\($0)" } ?? "nil")
                    return self.api.getPosts(type: listingType, sort: sortType, page: pageNumber)
                        .receive(on: self.backgroundScheduler)
                        .handleEvents(receiveOutput: { response in
                            os_log("Fetch feed complete with %{public}d posts",
                                   log: .lemmyService, type: .debug,
                                   response.posts.count)
                            feed.append(contentsOf: response.posts)
                        }, receiveCompletion: { completion in
                            switch completion {
                            case .failure:
                                break
                            case .finished:
                                self.saveIfNeeded()
                            }
                        })
                        .map { _ in () }
                        .eraseToAnyPublisher()
                }
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
}
