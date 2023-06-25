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

    func fetchComments(
        postId: NSManagedObjectID,
        sortType: CommentSortType
    ) -> AnyPublisher<Void, LemmyApiError>

    func fetchSiteInfo() -> AnyPublisher<Void, LemmyApiError>
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

        os_log("Creating new service for account %{public}@ instance %{public}@",
               log: .lemmyService, type: .info,
               accountObjectId.uriRepresentation().absoluteString,
               api.instanceHostname)
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
                os_log("Failed to save context for account %{public}@: %{public}@",
                       log: .lemmyService, type: .error,
                       accountObjectId.uriRepresentation().absoluteString,
                       String(describing: error))
            }
        }
    }

    func createFeed(_ type: LemmyFeed.FeedType) -> LemmyFeed {
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

    func createFeed(
        duplicateOf feed: LemmyFeed,
        sortType: SortType?
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

    func fetchFeed(
        feedId: NSManagedObjectID,
        page pageNumber: Int?
    ) -> AnyPublisher<Void, LemmyApiError> {
        assert(Thread.current.isMainThread)

        return object(with: feedId, type: LemmyFeed.self)
            .setFailureType(to: LemmyApiError.self)
            .flatMap { feed -> AnyPublisher<Void, LemmyApiError> in
                switch feed.feedType {
                case let .frontpage(listingType, sortType):
                    os_log("Fetch feed for account %{public}@. listingType=%{public}@ sortType=%{public}@ page=%{public}@",
                           log: .lemmyService, type: .debug,
                           self.accountObjectId.uriRepresentation().absoluteString,
                           listingType.rawValue, sortType.rawValue,
                           pageNumber.map { "\($0)" } ?? "nil")
                    let request = GetPosts.Request(
                        type_: listingType,
                        sort: sortType,
                        page: pageNumber
                    )
                    return self.api.getPosts(request)
                        .receive(on: self.backgroundScheduler)
                        .handleEvents(receiveOutput: { response in
                            os_log("Fetch feed for account %{public}@ complete with %{public}d posts",
                                   log: .lemmyService, type: .debug,
                                   self.accountObjectId.uriRepresentation().absoluteString,
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
                        .mapError { error in
                            os_log("Fetch feed for account %{public}@ failed: %{public}@",
                                   log: .lemmyService, type: .error,
                                   self.accountObjectId.uriRepresentation().absoluteString,
                                   String(describing: error))
                            return error
                        }
                        .map { _ in () }
                        .eraseToAnyPublisher()
                }
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    func fetchComments(
        postId: NSManagedObjectID,
        sortType: CommentSortType
    ) -> AnyPublisher<Void, LemmyApiError> {
        assert(Thread.current.isMainThread)

        return object(with: postId, type: LemmyPost.self)
            .setFailureType(to: LemmyApiError.self)
            .flatMap { post -> AnyPublisher<Void, LemmyApiError> in
                os_log("Fetch comments for account %{public}@. post=%{public}d",
                       log: .lemmyService, type: .debug,
                       self.accountObjectId.uriRepresentation().absoluteString,
                       post.localPostId)
                let request = GetComments.Request(
                    sort: sortType,
                    max_depth: 8,
                    post_id: post.localPostId
                )
                return self.api.getComments(request)
                    .receive(on: self.backgroundScheduler)
                    .handleEvents(receiveOutput: { response in
                        os_log("Fetch comments for account %{public}@ complete with %{public}d comments",
                               log: .lemmyService, type: .debug,
                               self.accountObjectId.uriRepresentation().absoluteString,
                               response.comments.count)
                        post.upsert(comments: response.comments, for: sortType)
                    }, receiveCompletion: { completion in
                        switch completion {
                        case .failure:
                            break
                        case .finished:
                            self.saveIfNeeded()
                        }
                    })
                    .mapError { error in
                        os_log("Fetch comments for account %{public}@ failed: %{public}@",
                               log: .lemmyService, type: .error,
                               self.accountObjectId.uriRepresentation().absoluteString,
                               String(describing: error))
                        return error
                    }
                    .map { _ in () }
                    .eraseToAnyPublisher()
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    func fetchSiteInfo() -> AnyPublisher<Void, LemmyApiError> {
        assert(Thread.current.isMainThread)

        return object(with: accountObjectId, type: LemmyAccount.self)
            .setFailureType(to: LemmyApiError.self)
            .flatMap { account -> AnyPublisher<Void, LemmyApiError> in
                os_log("Fetch site for account %{public}@",
                       log: .lemmyService, type: .debug,
                       self.accountObjectId.uriRepresentation().absoluteString)
                let request = GetSite.Request()
                return self.api.getSite(request)
                    .receive(on: self.backgroundScheduler)
                    .handleEvents(receiveOutput: { response in
                        os_log("Fetch site for account %{public}@ complete",
                               log: .lemmyService, type: .debug,
                               self.accountObjectId.uriRepresentation().absoluteString)
                        account.upsert(myUserInfo: response.my_user)
                        account.site.upsert(siteInfo: response)
                    }, receiveCompletion: { completion in
                        switch completion {
                        case .failure:
                            break
                        case .finished:
                            self.saveIfNeeded()
                        }
                    })
                    .mapError { error in
                        os_log("Fetch site for account %{public}@ failed: %{public}@",
                               log: .lemmyService, type: .error,
                               self.accountObjectId.uriRepresentation().absoluteString,
                               String(describing: error))
                        return error
                    }
                    .map { _ in () }
                    .eraseToAnyPublisher()
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
}
