//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import LemmyKit
import OSLog
import SpudUtilKit

private let logger = Logger(.lemmyService)

public enum LemmyServiceError: Error {
    case internalInconsistency(description: String)

    /// A low level API error has occurred.
    case apiError(LemmyApiError)

    init(from error: Error) {
        if let error = error as? LemmyApiError {
            self = .apiError(error)
        } else {
            assertionFailure("Unexpected exception \(type(of: error)): \(error))")
            self = .internalInconsistency(description: "Unexpected exception \(type(of: error)): \(error))")
        }
    }
}

public protocol LemmyServiceType {
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

    func fetchFeed(feedId: NSManagedObjectID, page pageNumber: Int64?) async throws

    func fetchComments(
        postId: NSManagedObjectID,
        sortType: Components.Schemas.CommentSortType
    ) async throws

    func fetchSiteInfo() async throws

    func fetchPersonInfo(
        personId: NSManagedObjectID
    ) async throws

    func vote(
        postId: NSManagedObjectID,
        vote action: VoteStatus.Action
    ) async throws

    func vote(
        commentId: NSManagedObjectID,
        vote action: VoteStatus.Action
    ) async throws

    func fetchPostInfo(
        postId: NSManagedObjectID
    ) async throws

    func getOrCreate(postId: Components.Schemas.PostID) -> LemmyPost

    func getOrCreate(personId: Components.Schemas.PersonID) -> LemmyPerson

    func markAsRead(
        postId: NSManagedObjectID
    ) async throws
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
        dataStore: DataStoreType,
        api: LemmyApi
    ) {
        accountObjectId = account.objectID
        accountIdentifierForLogging = account.identifierForLogging

        self.dataStore = dataStore
        self.api = api

        logger.info("Creating new service for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))")
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
    ) async -> CoreDataObject {
        await backgroundContext.perform(schedule: .immediate) {
            let object = self.backgroundContext.object(with: objectId)
            assert(object.entity == type.entity())
            let coreDataObject = object as! CoreDataObject
            return coreDataObject
        }
    }

    private func saveIfNeeded() {
        backgroundContext.performAndWait {
            backgroundContext.saveIfNeeded()
        }
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

    public func fetchFeed(feedId: NSManagedObjectID, page pageNumber: Int64?) async throws {
        let feed = await object(with: feedId, type: LemmyFeed.self)

        let response: Components.Schemas.GetPostsResponse

        do {
            switch feed.feedType {
            case let .frontpage(listingType, sortType):
                logger.debug("""
                    Fetch feed for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                    feedId=\(feed.id, privacy: .public) \
                    listingType=\(listingType.rawValue, privacy: .public) \
                    sortType=\(sortType.rawValue, privacy: .public) \
                    page=\(pageNumber.map { "\($0)" } ?? "nil", privacy: .public)
                    """)
                response = try await api.getPosts(
                    type: listingType,
                    sort: sortType,
                    page: pageNumber
                )

            case let .community(communityName, instance, sortType):
                logger.debug("""
                    Fetch feed for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                    feedId=\(feed.id, privacy: .public) \
                    communityName=\(communityName, privacy: .public) \
                    instance=\(instance.debugDescription, privacy: .public) \
                    sortType=\(sortType.rawValue, privacy: .public) \
                    page=\(pageNumber.map { "\($0)" } ?? "nil", privacy: .public)
                    """)
                response = try await api.getPosts(
                    community: .name("\(communityName)@\(instance.hostWithPort)"),
                    sort: sortType,
                    page: pageNumber
                )
            }
        } catch {
            logger.error("""
                Fetch feed failed. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                feedId=\(feed.id) \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("""
            Fetch feed complete with \(response.posts.count, privacy: .public) posts. \
            account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            feedId=\(feed.id, privacy: .public)
            """)

        feed.append(contentsOf: response.posts)

        saveIfNeeded()
    }

    public func fetchComments(
        postId: NSManagedObjectID,
        sortType: Components.Schemas.CommentSortType
    ) async throws {
        let post = await object(with: postId, type: LemmyPost.self)

        logger.debug("""
            Fetch comments for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
            post=\(post.identifierForLogging, privacy: .public) \
            sortType=\(sortType.rawValue, privacy: .public)
            """)

        let response: Components.Schemas.GetCommentsResponse
        do {
            response = try await api.getComments(
                postID: post.postId,
                sort: sortType,
                maxDepth: 8
            )
        } catch {
            logger.error("""
                Fetch comments failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("""
            Fetch comments for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            complete with \(response.comments.count, privacy: .public) comments
            """)
        post.upsert(comments: response.comments, for: sortType)

        saveIfNeeded()
    }

    public func fetchSiteInfo() async throws {
        let account = await object(with: accountObjectId, type: LemmyAccount.self)

        logger.debug("Fetch site for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))")

        let response: Components.Schemas.GetSiteResponse
        do {
            response = try await api.getSite()
        } catch {
            logger.error("""
                Fetch site failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("Fetch site complete. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))")
        account.upsert(myUserInfo: response.my_user)
        account.site.upsert(siteInfo: response)

        saveIfNeeded()
    }

    public func fetchPersonInfo(
        personId: NSManagedObjectID
    ) async throws {
        let person = await object(with: personId, type: LemmyPerson.self)

        logger.debug("Fetch person info for person=\(person.identifierForLogging, privacy: .public)")

        let response: Components.Schemas.GetPersonDetailsResponse
        do {
            response = try await api.getPersonDetails(personId: person.personId)
        } catch {
            logger.error("""
                Fetch person info failed. person=\(person.identifierForLogging, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("Fetch person info complete. person=\(person.identifierForLogging, privacy: .public)")

        person.set(from: response.person_view)
        assert(person.personInfo != nil)

        // TODO: upsert from response.posts
        // TODO: upsert from response.comments
        // TODO: upsert from response.moderates

        saveIfNeeded()
    }

    public func vote(
        postId: NSManagedObjectID,
        vote action: VoteStatus.Action
    ) async throws {
        let post = await object(with: postId, type: LemmyPost.self)

        guard let postInfo = post.postInfo else {
            logger.assertionFailure()
            throw LemmyServiceError.internalInconsistency(description: "missing post info")
        }

        let effectiveAction = postInfo.voteStatus.effectiveAction(for: action)

        logger.debug("""
            Vote '\(action, privacy: .public)' \
            (effective '\(effectiveAction, privacy: .public)') \
            for post=\(post.identifierForLogging, privacy: .public)
            """)

        let previousNumberOfUpvotes = postInfo.numberOfUpvotes
        let previousVoteStatus = postInfo.voteStatus

        // Update vote count to visually indicate something is happening
        postInfo.numberOfUpvotes += postInfo.voteStatus.voteCountChange(for: action)

        // Set the vote status to the new value without waiting for confirmation from the server.
        switch effectiveAction {
        case .liked:
            postInfo.voteStatus = .up
        case .disliked:
            postInfo.voteStatus = .down
        case .neutral:
            postInfo.voteStatus = .neutral
        }

        let response: Components.Schemas.PostResponse
        do {
            response = try await api.likePost(post.postId, status: effectiveAction)
        } catch {
            logger.error("""
                Vote failed. post=\(post.identifierForLogging, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)

            postInfo.voteStatus = previousVoteStatus
            postInfo.numberOfUpvotes = previousNumberOfUpvotes

            saveIfNeeded()

            throw LemmyServiceError(from: error)
        }

        post.set(from: response.post_view)

        saveIfNeeded()
    }

    public func vote(
        commentId: NSManagedObjectID,
        vote action: VoteStatus.Action
    ) async throws {
        let comment = await object(with: commentId, type: LemmyComment.self)

        let effectiveAction = comment.voteStatus.effectiveAction(for: action)

        logger.debug("""
            Vote '\(action, privacy: .public)' \
            (effective '\(effectiveAction, privacy: .public)') \
            for comment=\(comment.identifierForLogging, privacy: .public)
            """)

        let previousNumberOfUpvotes = comment.numberOfUpvotes
        let previousVoteStatus = comment.voteStatus

        // Update vote count to visually indicate something is happening
        comment.numberOfUpvotes += comment.voteStatus.voteCountChange(for: action)

        // Set the vote status to the new value without waiting for confirmation from the server.
        switch effectiveAction {
        case .liked:
            comment.voteStatus = .up
        case .disliked:
            comment.voteStatus = .down
        case .neutral:
            comment.voteStatus = .neutral
        }

        let response: Components.Schemas.CommentResponse
        do {
            response = try await api.likeComment(comment.localCommentId, status: effectiveAction)
        } catch {
            comment.voteStatus = previousVoteStatus
            comment.numberOfUpvotes = previousNumberOfUpvotes

            saveIfNeeded()

            throw LemmyServiceError(from: error)
        }

        comment.set(from: response.comment_view)

        saveIfNeeded()
    }

    public func fetchPostInfo(
        postId: NSManagedObjectID
    ) async throws {
        let post = await object(with: postId, type: LemmyPost.self)

        logger.debug("Fetch post. post=\(post.identifierForLogging, privacy: .public)")

        let response: Components.Schemas.GetPostResponse
        do {
            response = try await api.getPost(id: post.postId)
        } catch {
            logger.error("""
                Fetch post failed. post=\(post.identifierForLogging, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("Fetch post complete. post=\(post.identifierForLogging, privacy: .public)")

        post.set(from: response.post_view)

        assert(post.postInfo != nil)
        post.postInfo?.community.set(from: response.community_view)

        // TODO: upsert from response.moderators
        // TODO: upsert from response.cross_posts

        saveIfNeeded()
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

    public func markAsRead(
        postId: NSManagedObjectID
    ) async throws {
        let post = await object(with: postId, type: LemmyPost.self)

        logger.debug("Marking post as read. post=\(post.identifierForLogging, privacy: .public)")

        let response: Components.Schemas.SuccessResponse
        do {
            response = try await api.markPostAsRead(postIds: [post.postId], read: true)
        } catch {
            logger.error("""
                Mark post as read failed. post=\(post.identifierForLogging, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("Mark post as read complete. post=\(post.identifierForLogging, privacy: .public); success=\(response.success)")
        assert(post.postInfo != nil)
        post.postInfo?.isRead = response.success

        saveIfNeeded()
    }
}
