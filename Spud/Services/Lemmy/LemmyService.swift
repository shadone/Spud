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

private let logger = Logger(.lemmyService)

enum LemmyServiceError: Error {
    /// The request request authentication but the current LemmyService is signed out kind.
    case missingCredential

    /// A low level API error has occurred.
    case apiError(LemmyApiError)
}

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

    func vote(
        postId: NSManagedObjectID,
        vote action: VoteStatus.Action
    ) -> AnyPublisher<Void, LemmyServiceError>
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

        logger.info("Creating new service for \(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))")
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
                    logger.debug("""
                        Fetch feed for \(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                        listingType=\(listingType.rawValue, privacy: .public) \
                        sortType=\(sortType.rawValue, privacy: .public) \
                        page=\(pageNumber.map { "\($0)" } ?? "nil", privacy: .public)
                        """)
                    let request = GetPosts.Request(
                        type_: listingType,
                        sort: sortType,
                        page: pageNumber,
                        auth: self.credential?.jwt
                    )
                    return self.api.getPosts(request)
                        .receive(on: self.backgroundScheduler)
                        .handleEvents(receiveOutput: { response in
                            logger.debug("""
                                Fetch feed for \(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                                complete with \(response.posts.count, privacy: .public) posts
                                """)
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
                            logger.error("""
                                Fetch feed for \(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                                failed: \(String(describing: error), privacy: .public)
                                """)
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
                logger.debug("""
                    Fetch comments for \(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                    post=\(post.localPostId, privacy: .public)
                    """)
                let request = GetComments.Request(
                    sort: sortType,
                    max_depth: 8,
                    post_id: post.localPostId,
                    auth: self.credential?.jwt
                )
                return self.api.getComments(request)
                    .receive(on: self.backgroundScheduler)
                    .handleEvents(receiveOutput: { response in
                        logger.debug("""
                            Fetch comments for \(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                            complete with \(response.comments.count, privacy: .public) comments
                            """)
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
                        logger.error("""
                            Fetch comments for \(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                            failed: \(String(describing: error), privacy: .public)
                            """)
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
                logger.debug("Fetch site for \(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))")
                let request = GetSite.Request(
                    auth: self.credential?.jwt
                )
                return self.api.getSite(request)
                    .receive(on: self.backgroundScheduler)
                    .handleEvents(receiveOutput: { response in
                        logger.debug("Fetch site for \(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) complete")
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
                        logger.error("""
                            Fetch site for \(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                            failed: \(String(describing: error), privacy: .public)
                            """)
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
                logger.debug("Fetch person info for \(person.identifierForLogging, privacy: .public)")
                let request = GetPersonDetails.Request(
                    person_id: person.personId,
                    auth: self.credential?.jwt
                )
                return self.api.getPersonDetails(request)
                    .receive(on: self.backgroundScheduler)
                    .map { response -> LemmyPersonInfo in
                        logger.debug("Fetch person info for \(person.identifierForLogging, privacy: .public) complete")

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
                        logger.error("""
                            Fetch person info for \(person.identifierForLogging, privacy: .public) \
                            failed: \(String(describing: error), privacy: .public)
                            """)
                        return error
                    }
                    .eraseToAnyPublisher()
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    func vote(
        postId: NSManagedObjectID,
        vote action: VoteStatus.Action
    ) -> AnyPublisher<Void, LemmyServiceError> {
        assert(Thread.current.isMainThread)

        return object(with: postId, type: LemmyPost.self)
            .setFailureType(to: LemmyServiceError.self)
            .flatMap { post -> AnyPublisher<Void, LemmyServiceError> in
                let effectiveAction = post.voteStatus.effectiveAction(for: action)

                logger.debug("""
                    Vote '\(action, privacy: .public)' \
                    (effective '\(effectiveAction, privacy: .public)') \
                    for \(post.identifierForLogging, privacy: .public)
                    """)

                let previousNumberOfUpvotes = post.numberOfUpvotes
                let previousVoteStatus = post.voteStatus

                // Update vote count to visually indicate something is happening
                post.numberOfUpvotes += post.voteStatus.voteCountChange(for: action)

                // Set the vote status to the new value without waiting for confirmation from the server.
                switch effectiveAction {
                case .upvote:
                    post.voteStatus = .up
                case .downvote:
                    post.voteStatus = .down
                case .unvote:
                    post.voteStatus = .neutral
                }

                guard let credential = self.credential else {
                    return .fail(with: .missingCredential)
                }

                let request = CreatePostLike.Request(
                    post_id: post.localPostId,
                    score: effectiveAction,
                    auth: credential.jwt
                )
                return self.api.createPostLike(request)
                    .receive(on: self.backgroundScheduler)
                    .handleEvents(receiveOutput: { response in
                        post.set(from: response.post_view)
                    }, receiveCompletion: { completion in
                        switch completion {
                        case .failure:
                            post.voteStatus = previousVoteStatus
                            post.numberOfUpvotes = previousNumberOfUpvotes
                            self.saveIfNeeded()
                        case .finished:
                            self.saveIfNeeded()
                        }
                    })
                    .map { _ in () }
                    .mapError { .apiError($0) }
                    .eraseToAnyPublisher()
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
}
