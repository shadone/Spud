//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import LemmyKit
import os.log
import SpudUtilKit

private let logger = Logger(.lemmyService)

public enum LemmyServiceError: Error {
    /// The request request authentication but the current LemmyService is signed out kind.
    case missingCredential

    case internalInconsistency(description: String)

    /// A low level API error has occurred.
    case apiError(LemmyApiError)
}

public protocol LemmyServiceType {
    /// Creates feed with default parameters for the account.
    func createFeed() -> LemmyFeed

    /// Creates feed for the given ``listingType`` with default sort type parameters for the account.
    func createFeed(listingType: ListingType) -> LemmyFeed

    /// Creates feed with the explicitly given feed parameters.
    func createFeed(_ type: FeedType) -> LemmyFeed

    func createFeed(duplicateOf feed: LemmyFeed) -> LemmyFeed

    func createFeed(duplicateOf feed: LemmyFeed, sortType: SortType?) -> LemmyFeed

    func fetchFeed(
        feedId: NSManagedObjectID,
        page pageNumber: Int64?
    ) -> AnyPublisher<Void, LemmyServiceError>

    func fetchComments(
        postId: NSManagedObjectID,
        sortType: CommentSortType
    ) -> AnyPublisher<Void, LemmyServiceError>

    func fetchSiteInfo() -> AnyPublisher<Void, LemmyServiceError>

    func fetchPersonInfo(
        personId: NSManagedObjectID
    ) -> AnyPublisher<Void, LemmyServiceError>

    func vote(
        postId: NSManagedObjectID,
        vote action: VoteStatus.Action
    ) -> AnyPublisher<Void, LemmyServiceError>

    func vote(
        commentId: NSManagedObjectID,
        vote action: VoteStatus.Action
    ) -> AnyPublisher<Void, LemmyServiceError>

    func fetchPostInfo(
        postId: NSManagedObjectID
    ) -> AnyPublisher<Void, LemmyServiceError>

    func getOrCreate(postId: PostId) -> LemmyPost

    func getOrCreate(personId: PersonId) -> LemmyPerson

    func markAsRead(
        postId: NSManagedObjectID
    ) -> AnyPublisher<Void, LemmyServiceError>
}

public extension LemmyServiceType {
    func createFeed(duplicateOf feed: LemmyFeed) -> LemmyFeed {
        createFeed(duplicateOf: feed, sortType: nil)
    }
}

public class LemmyService: LemmyServiceType {
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
        backgroundContext.name = "background[\(accountIdentifierForLogging)]"
        return backgroundContext
    }()

    private lazy var backgroundScheduler: ManagedContextSchedulerOf<DispatchQueue> = DispatchQueue.managedContentScheduler(backgroundContext)

    /// Returns account object in **background context**.
    private var account: LemmyAccount {
        backgroundContext.object(with: accountObjectId) as! LemmyAccount
    }

    /// Returns account object in **main context**.
    private var accountInMainContext: LemmyAccount {
        dataStore.mainContext.object(with: accountObjectId) as! LemmyAccount
    }

    // MARK: Functions

    init(
        account: LemmyAccount,
        credential: LemmyCredential?,
        dataStore: DataStoreType,
        api: LemmyApi
    ) {
        accountObjectId = account.objectID
        accountIdentifierForLogging = account.identifierForLogging

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

    private func defaultListingType(for account: LemmyAccount) -> ListingType {
        lazy var siteListingType = accountInMainContext.site.siteInfo?.defaultPostListingType
        let userListingType = accountInMainContext.accountInfo?.defaultListingType
        return userListingType ?? siteListingType ?? .all
    }

    private func defaultSortType(for account: LemmyAccount) -> SortType {
        let userSortType = accountInMainContext.accountInfo?.defaultSortType
        return userSortType ?? .hot
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

    public func createFeed(listingType: ListingType) -> LemmyFeed {
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

    public func fetchFeed(
        feedId: NSManagedObjectID,
        page pageNumber: Int64?
    ) -> AnyPublisher<Void, LemmyServiceError> {
        assert(Thread.current.isMainThread)

        return object(with: feedId, type: LemmyFeed.self)
            .setFailureType(to: LemmyServiceError.self)
            .flatMap { feed -> AnyPublisher<Void, LemmyServiceError> in
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
                        .map { response in
                            logger.debug("""
                                Fetch feed for \(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                                complete with \(response.posts.count, privacy: .public) posts
                                """)

                            feed.append(contentsOf: response.posts)

                            self.saveIfNeeded()

                            return ()
                        }
                        .mapError { error in
                            logger.error("""
                                Fetch feed for \(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                                failed: \(String(describing: error), privacy: .public)
                                """)
                            return .apiError(error)
                        }
                        .eraseToAnyPublisher()
                }
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    public func fetchComments(
        postId: NSManagedObjectID,
        sortType: CommentSortType
    ) -> AnyPublisher<Void, LemmyServiceError> {
        assert(Thread.current.isMainThread)

        return object(with: postId, type: LemmyPost.self)
            .setFailureType(to: LemmyServiceError.self)
            .flatMap { post -> AnyPublisher<Void, LemmyServiceError> in
                logger.debug("""
                    Fetch comments for \(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                    post=\(post.postId, privacy: .public) \
                    sortType=\(sortType.rawValue, privacy: .public)
                    """)
                let request = GetComments.Request(
                    sort: sortType,
                    max_depth: 8,
                    post_id: post.postId,
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
                        return .apiError(error)
                    }
                    .map { _ in () }
                    .eraseToAnyPublisher()
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    public func fetchSiteInfo() -> AnyPublisher<Void, LemmyServiceError> {
        assert(Thread.current.isMainThread)

        return object(with: accountObjectId, type: LemmyAccount.self)
            .setFailureType(to: LemmyServiceError.self)
            .flatMap { account -> AnyPublisher<Void, LemmyServiceError> in
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
                        return .apiError(error)
                    }
                    .map { _ in () }
                    .eraseToAnyPublisher()
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    public func fetchPersonInfo(
        personId: NSManagedObjectID
    ) -> AnyPublisher<Void, LemmyServiceError> {
        assert(Thread.current.isMainThread)

        return object(with: personId, type: LemmyPerson.self)
            .setFailureType(to: LemmyServiceError.self)
            .flatMap { person -> AnyPublisher<Void, LemmyServiceError> in
                logger.debug("Fetch person info for \(person.identifierForLogging, privacy: .public)")
                let request = GetPersonDetails.Request(
                    person_id: person.personId,
                    auth: self.credential?.jwt
                )
                return self.api.getPersonDetails(request)
                    .receive(on: self.backgroundScheduler)
                    .handleEvents(receiveOutput: { response in
                        logger.debug("Fetch person info for \(person.identifierForLogging, privacy: .public) complete")

                        person.set(from: response.person_view)
                        assert(person.personInfo != nil)

                        // TODO: upsert from response.posts
                        // TODO: upsert from response.comments
                        // TODO: upsert from response.moderates
                    }, receiveCompletion: { completion in
                        switch completion {
                        case .failure:
                            break
                        case .finished:
                            self.saveIfNeeded()
                        }
                    })
                    .map { _ in () }
                    .mapError { error in
                        logger.error("""
                            Fetch person info for \(person.identifierForLogging, privacy: .public) \
                            failed: \(String(describing: error), privacy: .public)
                            """)
                        return .apiError(error)
                    }
                    .eraseToAnyPublisher()
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    public func vote(
        postId: NSManagedObjectID,
        vote action: VoteStatus.Action
    ) -> AnyPublisher<Void, LemmyServiceError> {
        assert(Thread.current.isMainThread)

        return object(with: postId, type: LemmyPost.self)
            .setFailureType(to: LemmyServiceError.self)
            .flatMap { post -> AnyPublisher<Void, LemmyServiceError> in
                guard let postInfo = post.postInfo else {
                    assertionFailure()
                    return .fail(with: .internalInconsistency(description: "missing post info"))
                }

                let effectiveAction = postInfo.voteStatus.effectiveAction(for: action)

                logger.debug("""
                    Vote '\(action, privacy: .public)' \
                    (effective '\(effectiveAction, privacy: .public)') \
                    for \(post.identifierForLogging, privacy: .public)
                    """)

                let previousNumberOfUpvotes = postInfo.numberOfUpvotes
                let previousVoteStatus = postInfo.voteStatus

                // Update vote count to visually indicate something is happening
                postInfo.numberOfUpvotes += postInfo.voteStatus.voteCountChange(for: action)

                // Set the vote status to the new value without waiting for confirmation from the server.
                switch effectiveAction {
                case .upvote:
                    postInfo.voteStatus = .up
                case .downvote:
                    postInfo.voteStatus = .down
                case .unvote:
                    postInfo.voteStatus = .neutral
                }

                guard let credential = self.credential else {
                    return .fail(with: .missingCredential)
                }

                let request = CreatePostLike.Request(
                    post_id: post.postId,
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
                            postInfo.voteStatus = previousVoteStatus
                            postInfo.numberOfUpvotes = previousNumberOfUpvotes
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

    public func vote(
        commentId: NSManagedObjectID,
        vote action: VoteStatus.Action
    ) -> AnyPublisher<Void, LemmyServiceError> {
        assert(Thread.current.isMainThread)

        return object(with: commentId, type: LemmyComment.self)
            .setFailureType(to: LemmyServiceError.self)
            .flatMap { comment -> AnyPublisher<Void, LemmyServiceError> in
                let effectiveAction = comment.voteStatus.effectiveAction(for: action)

                logger.debug("""
                    Vote '\(action, privacy: .public)' \
                    (effective '\(effectiveAction, privacy: .public)') \
                    for \(comment.identifierForLogging, privacy: .public)
                    """)

                let previousNumberOfUpvotes = comment.numberOfUpvotes
                let previousVoteStatus = comment.voteStatus

                // Update vote count to visually indicate something is happening
                comment.numberOfUpvotes += comment.voteStatus.voteCountChange(for: action)

                // Set the vote status to the new value without waiting for confirmation from the server.
                switch effectiveAction {
                case .upvote:
                    comment.voteStatus = .up
                case .downvote:
                    comment.voteStatus = .down
                case .unvote:
                    comment.voteStatus = .neutral
                }

                guard let credential = self.credential else {
                    return .fail(with: .missingCredential)
                }

                let request = CreateCommentLike.Request(
                    comment_id: comment.localCommentId,
                    score: effectiveAction,
                    auth: credential.jwt
                )
                return self.api.createCommentLike(request)
                    .receive(on: self.backgroundScheduler)
                    .handleEvents(receiveOutput: { response in
                        comment.set(from: response.comment_view)
                    }, receiveCompletion: { completion in
                        switch completion {
                        case .failure:
                            comment.voteStatus = previousVoteStatus
                            comment.numberOfUpvotes = previousNumberOfUpvotes
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

    public func fetchPostInfo(
        postId: NSManagedObjectID
    ) -> AnyPublisher<Void, LemmyServiceError> {
        assert(Thread.current.isMainThread)

        return object(with: postId, type: LemmyPost.self)
            .setFailureType(to: LemmyServiceError.self)
            .flatMap { post -> AnyPublisher<Void, LemmyServiceError> in
                logger.debug("Fetch post \(post.postId, privacy: .public)")
                let request = GetPost.Request(
                    id: post.postId,
                    auth: self.credential?.jwt
                )
                return self.api.getPost(request)
                    .receive(on: self.backgroundScheduler)
                    .handleEvents(receiveOutput: { response in
                        logger.debug("Fetch post \(post.postId, privacy: .public) complete")

                        post.set(from: response.post_view)

                        assert(post.postInfo != nil)
                        post.postInfo?.community.set(from: response.community_view)

                        // TODO: upsert from response.moderators
                        // TODO: upsert from response.cross_posts
                    }, receiveCompletion: { completion in
                        switch completion {
                        case .failure:
                            break
                        case .finished:
                            self.saveIfNeeded()
                        }
                    })
                    .map { _ in () }
                    .mapError { error in
                        logger.error("""
                            Fetch post \(post.postId, privacy: .public) \
                            failed: \(String(describing: error), privacy: .public)
                            """)
                        return .apiError(error)
                    }
                    .eraseToAnyPublisher()
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    public func getOrCreate(postId: PostId) -> LemmyPost {
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

    public func getOrCreate(personId: PersonId) -> LemmyPerson {
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

    public func markAsRead(
        postId: NSManagedObjectID
    ) -> AnyPublisher<Void, LemmyServiceError> {
        assert(Thread.current.isMainThread)

        return object(with: postId, type: LemmyPost.self)
            .setFailureType(to: LemmyServiceError.self)
            .flatMap { post -> AnyPublisher<Void, LemmyServiceError> in
                logger.debug("Marking post as read \(post.postId, privacy: .public)")

                guard let credential = self.credential else {
                    return .fail(with: .missingCredential)
                }

                let request = MarkPostAsRead.Request(
                    post_id: post.postId,
                    read: true,
                    auth: credential.jwt
                )
                return self.api.markPostAsRead(request)
                    .receive(on: self.backgroundScheduler)
                    .handleEvents(receiveOutput: { response in
                        logger.debug("Mark post as read \(post.postId, privacy: .public) complete")
                        post.set(from: response.post_view)
                    }, receiveCompletion: { completion in
                        switch completion {
                        case .failure:
                            break
                        case .finished:
                            self.saveIfNeeded()
                        }
                    })
                    .map { _ in () }
                    .mapError { error in
                        logger.error("""
                            Mark post as read \(post.postId, privacy: .public) \
                            failed: \(String(describing: error), privacy: .public)
                            """)
                        return .apiError(error)
                    }
                    .eraseToAnyPublisher()
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
}
