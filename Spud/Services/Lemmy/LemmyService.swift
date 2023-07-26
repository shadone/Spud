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
        page pageNumber: Int64?
    ) -> AnyPublisher<Void, LemmyApiError>

    func fetchComments(
        postId: NSManagedObjectID,
        sortType: CommentSortType
    ) -> AnyPublisher<Void, LemmyApiError>

    func fetchSiteInfo() -> AnyPublisher<Void, LemmyApiError>

    func fetchPersonDetails(
        personId: NSManagedObjectID
    ) -> AnyPublisher<LemmyPersonInfo, LemmyApiError>
}

extension LemmyServiceType {
    func createFeed(duplicateOf feed: LemmyFeed) -> LemmyFeed {
        createFeed(duplicateOf: feed, sortType: nil)
    }
}

class LemmyService: LemmyServiceType {
    // MARK: Public

    let accountObjectId: NSManagedObjectID
    @Atomic var accountIdentifierForLogging: String

    // MARK: Private

    private let credential: LemmyCredential?
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
        account: LemmyAccount,
        credential: LemmyCredential?,
        dataStore: DataStoreType,
        api: LemmyApi
    ) {
        self.accountObjectId = account.objectID
        self.accountIdentifierForLogging = account.identifierForLogging

        self.credential = credential
        self.dataStore = dataStore
        self.api = api

        os_log("Creating new service for %{public}@",
               log: .lemmyService, type: .info,
               accountIdentifierForLogging)
    }

    private func object<CoreDataObject>(
        with objectId: NSManagedObjectID,
        type _: CoreDataObject.Type
    ) async -> CoreDataObject {
        await backgroundContext.perform {
            self.backgroundContext.object(with: objectId) as! CoreDataObject
        }
    }

    private func object<CoreDataObject: NSManagedObject>(
        with objectId: NSManagedObjectID,
        type: CoreDataObject.Type
    ) -> AnyPublisher<CoreDataObject, Never> {
        Future<CoreDataObject, Never> { promise in
            self.backgroundContext.perform {
                let object = self.backgroundContext.object(with: objectId)
                assert(object.entity == type.entity())
                let coreDataObject = object as! CoreDataObject
                promise(.success(coreDataObject))
            }
        }
        .subscribe(on: backgroundScheduler)
        .eraseToAnyPublisher()
    }

    private func saveIfNeeded() {
        backgroundContext.performAndWait {
            backgroundContext.saveIfNeeded()
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
        page pageNumber: Int64?
    ) -> AnyPublisher<Void, LemmyApiError> {
        assert(Thread.current.isMainThread)

        return object(with: feedId, type: LemmyFeed.self)
            .setFailureType(to: LemmyApiError.self)
            .flatMap { feed -> AnyPublisher<Void, LemmyApiError> in
                switch feed.feedType {
                case let .frontpage(listingType, sortType):
                    os_log("Fetch feed for %{public}@. listingType=%{public}@ sortType=%{public}@ page=%{public}@",
                           log: .lemmyService, type: .debug,
                           self.accountIdentifierForLogging,
                           listingType.rawValue, sortType.rawValue,
                           pageNumber.map { "\($0)" } ?? "nil")
                    let request = GetPosts.Request(
                        type_: listingType,
                        sort: sortType,
                        page: pageNumber,
                        auth: self.credential?.jwt
                    )
                    return self.api.getPosts(request)
                        .receive(on: self.backgroundScheduler)
                        .handleEvents(receiveOutput: { response in
                            os_log("Fetch feed for %{public}@ complete with %{public}d posts",
                                   log: .lemmyService, type: .debug,
                                   self.accountIdentifierForLogging,
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
                            os_log("Fetch feed for %{public}@ failed: %{public}@",
                                   log: .lemmyService, type: .error,
                                   self.accountIdentifierForLogging,
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
                os_log("Fetch comments for %{public}@. post=%{public}d",
                       log: .lemmyService, type: .debug,
                       self.accountIdentifierForLogging,
                       post.localPostId)
                let request = GetComments.Request(
                    sort: sortType,
                    max_depth: 8,
                    post_id: post.localPostId,
                    auth: self.credential?.jwt
                )
                return self.api.getComments(request)
                    .receive(on: self.backgroundScheduler)
                    .handleEvents(receiveOutput: { response in
                        os_log("Fetch comments for %{public}@ complete with %{public}d comments",
                               log: .lemmyService, type: .debug,
                               self.accountIdentifierForLogging,
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
                        os_log("Fetch comments for %{public}@ failed: %{public}@",
                               log: .lemmyService, type: .error,
                               self.accountIdentifierForLogging,
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
                os_log("Fetch site for %{public}@",
                       log: .lemmyService, type: .debug,
                       self.accountIdentifierForLogging)
                let request = GetSite.Request(
                    auth: self.credential?.jwt
                )
                return self.api.getSite(request)
                    .receive(on: self.backgroundScheduler)
                    .handleEvents(receiveOutput: { response in
                        os_log("Fetch site for %{public}@ complete",
                               log: .lemmyService, type: .debug,
                               self.accountIdentifierForLogging)
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
                        os_log("Fetch site for %{public}@ failed: %{public}@",
                               log: .lemmyService, type: .error,
                               self.accountIdentifierForLogging,
                               String(describing: error))
                        return error
                    }
                    .map { _ in () }
                    .eraseToAnyPublisher()
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    func fetchPersonDetails(
        personId: NSManagedObjectID
    ) -> AnyPublisher<LemmyPersonInfo, LemmyApiError> {
        assert(Thread.current.isMainThread)

        return object(with: personId, type: LemmyPerson.self)
            .setFailureType(to: LemmyApiError.self)
            .flatMap { person -> AnyPublisher<LemmyPersonInfo, LemmyApiError> in
                os_log("Fetch person info for %{public}@",
                       log: .lemmyService, type: .debug,
                       person.identifierForLogging)
                let request = GetPersonDetails.Request(
                    person_id: person.personId,
                    auth: self.credential?.jwt
                )
                return self.api.getPersonDetails(request)
                    .receive(on: self.backgroundScheduler)
                    .map { response -> LemmyPersonInfo in
                        os_log("Fetch person info for %{public}@ complete",
                               log: .lemmyService, type: .debug,
                               person.identifierForLogging)

                        person.set(from: response.person_view)

                        assert(person.personInfo != nil)
                        return person.personInfo!
                    }
                    .handleEvents(receiveOutput: { response in
                    }, receiveCompletion: { completion in
                        switch completion {
                        case .failure:
                            break
                        case .finished:
                            self.saveIfNeeded()
                        }
                    })
                    .mapError { error in
                        os_log("Fetch person info for %{public}@ failed: %{public}@",
                               log: .lemmyService, type: .error,
                               person.identifierForLogging,
                               String(describing: error))
                        return error
                    }
                    .eraseToAnyPublisher()
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
}
