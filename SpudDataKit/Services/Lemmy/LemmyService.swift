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

private let logger = Logger.lemmyService

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

public protocol LemmyServiceType: Actor {
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

    func markAsRead(
        postId: NSManagedObjectID
    ) async throws
}

public actor LemmyService: LemmyServiceType {
    // MARK: Public

    let accountObjectId: NSManagedObjectID
    let accountIdentifierForLogging: String

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

    private func perform<CoreDataObject: NSManagedObject, T>(
        with objectId: NSManagedObjectID,
        type: CoreDataObject.Type,
        _ closure: @escaping (CoreDataObject, NSManagedObjectContext) -> T
    ) async -> T {
        await backgroundContext.perform(schedule: .immediate) {
            let object = self.backgroundContext.object(with: objectId)
            assert(object.entity == type.entity())
            let coreDataObject = object as! CoreDataObject
            return closure(coreDataObject, self.backgroundContext)
        }
    }

    private func perform<CoreDataObject: NSManagedObject, T>(
        with objectId: NSManagedObjectID,
        type: CoreDataObject.Type,
        _ closure: @escaping (CoreDataObject, NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await backgroundContext.perform(schedule: .immediate) {
            let object = self.backgroundContext.object(with: objectId)
            assert(object.entity == type.entity())
            let coreDataObject = object as! CoreDataObject
            return try closure(coreDataObject, self.backgroundContext)
        }
    }

    public func fetchFeed(feedId feedObjectId: NSManagedObjectID, page pageNumber: Int64?) async throws {
        let (feedType, feedId) = await perform(
            with: feedObjectId,
            type: LemmyFeed.self
        ) { feed, _ in
            (feed.feedType, feed.id)
        }

        let response: Components.Schemas.GetPostsResponse

        do {
            switch feedType {
            case let .frontpage(listingType, sortType):
                logger.debug("""
                    Fetch feed for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                    feedId=\(feedId, privacy: .public) \
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
                    feedId=\(feedId, privacy: .public) \
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
                feedId=\(feedId) \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("""
            Fetch feed complete with \(response.posts.count, privacy: .public) posts. \
            account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            feedId=\(feedId, privacy: .public)
            """)

        await perform(with: feedObjectId, type: LemmyFeed.self) { feed, context in
            feed.append(contentsOf: response.posts)
            context.saveIfNeeded()
        }
    }

    public func fetchComments(
        postId postObjectId: NSManagedObjectID,
        sortType: Components.Schemas.CommentSortType
    ) async throws {
        let (postId, postIdentifierForLogging) = await perform(
            with: postObjectId,
            type: LemmyPost.self
        ) { post, _ in
            (post.postId, post.identifierForLogging)
        }

        logger.debug("""
            Fetch comments for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
            post=\(postIdentifierForLogging, privacy: .public) \
            sortType=\(sortType.rawValue, privacy: .public)
            """)

        let response: Components.Schemas.GetCommentsResponse
        do {
            response = try await api.getComments(
                postID: postId,
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

        await perform(with: postObjectId, type: LemmyPost.self) { post, context in
            post.upsert(comments: response.comments, for: sortType)
            context.saveIfNeeded()
        }
    }

    public func fetchSiteInfo() async throws {
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

        await perform(
            with: accountObjectId,
            type: LemmyAccount.self
        ) { account, context in
            account.upsert(myUserInfo: response.my_user)
            account.site.upsert(siteInfo: response)

            context.saveIfNeeded()
        }
    }

    public func fetchPersonInfo(
        personId personObjectId: NSManagedObjectID
    ) async throws {
        let (personId, personIdentifierForLogging) = await perform(
            with: personObjectId,
            type: LemmyPerson.self
        ) { person, _ in
            (person.personId, person.identifierForLogging)
        }

        logger.debug("Fetch person info for person=\(personIdentifierForLogging, privacy: .public)")

        let response: Components.Schemas.GetPersonDetailsResponse
        do {
            response = try await api.getPersonDetails(personId: personId)
        } catch {
            logger.error("""
                Fetch person info failed. person=\(personIdentifierForLogging, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("Fetch person info complete. person=\(personIdentifierForLogging, privacy: .public)")

        await perform(with: personObjectId, type: LemmyPerson.self) { person, context in
            person.set(from: response.person_view)
            assert(person.personInfo != nil)

            // TODO: upsert from response.posts
            // TODO: upsert from response.comments
            // TODO: upsert from response.moderates

            context.saveIfNeeded()
        }
    }

    public func vote(
        postId postObjectId: NSManagedObjectID,
        vote action: VoteStatus.Action
    ) async throws {
        let (
            postId, postIdentifierForLogging,
            effectiveAction,
            previousVoteStatus, previousNumberOfUpvotes
        ) = try await perform(
            with: postObjectId,
            type: LemmyPost.self
        ) { post, _ in
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

            return (
                post.postId, post.identifierForLogging,
                effectiveAction,
                previousVoteStatus, previousNumberOfUpvotes
            )
        }

        let response: Components.Schemas.PostResponse
        do {
            response = try await api.likePost(postId, status: effectiveAction)
        } catch {
            logger.error("""
                Vote failed. post=\(postIdentifierForLogging, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)

            await perform(with: postObjectId, type: LemmyPost.self) { post, context in
                post.postInfo?.voteStatus = previousVoteStatus
                post.postInfo?.numberOfUpvotes = previousNumberOfUpvotes

                context.saveIfNeeded()
            }

            throw LemmyServiceError(from: error)
        }

        await perform(with: postObjectId, type: LemmyPost.self) { post, context in
            post.set(from: response.post_view)

            context.saveIfNeeded()
        }
    }

    public func vote(
        commentId commentObjectId: NSManagedObjectID,
        vote action: VoteStatus.Action
    ) async throws {
        let (
            localCommentId,
            effectiveAction,
            previousVoteStatus, previousNumberOfUpvotes
        ) = await perform(with: commentObjectId, type: LemmyComment.self) { comment, _ in
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

            return (
                comment.localCommentId,
                effectiveAction,
                previousVoteStatus, previousNumberOfUpvotes
            )
        }

        let response: Components.Schemas.CommentResponse
        do {
            response = try await api.likeComment(localCommentId, status: effectiveAction)
        } catch {
            await perform(with: commentObjectId, type: LemmyComment.self) { comment, context in
                comment.voteStatus = previousVoteStatus
                comment.numberOfUpvotes = previousNumberOfUpvotes

                context.saveIfNeeded()
            }

            throw LemmyServiceError(from: error)
        }

        await perform(with: commentObjectId, type: LemmyComment.self) { comment, context in
            comment.set(from: response.comment_view)

            context.saveIfNeeded()
        }
    }

    public func fetchPostInfo(
        postId postObjectId: NSManagedObjectID
    ) async throws {
        let (postId, postIdentifierForLogging) = await perform(
            with: postObjectId,
            type: LemmyPost.self
        ) { post, _ in
            (post.postId, post.identifierForLogging)
        }

        logger.debug("Fetch post. post=\(postIdentifierForLogging, privacy: .public)")

        let response: Components.Schemas.GetPostResponse
        do {
            response = try await api.getPost(id: postId)
        } catch {
            logger.error("""
                Fetch post failed. post=\(postIdentifierForLogging, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("Fetch post complete. post=\(postIdentifierForLogging, privacy: .public)")

        await perform(with: postObjectId, type: LemmyPost.self) { post, context in
            post.set(from: response.post_view)

            assert(post.postInfo != nil)
            post.postInfo?.community.set(from: response.community_view)

            // TODO: upsert from response.moderators
            // TODO: upsert from response.cross_posts

            context.saveIfNeeded()
        }
    }

    public func markAsRead(
        postId postObjectId: NSManagedObjectID
    ) async throws {
        let (postId, postIdentifierForLogging) = await perform(
            with: postObjectId,
            type: LemmyPost.self
        ) { post, _ in
            (post.postId, post.identifierForLogging)
        }

        logger.debug("Marking post as read. post=\(postIdentifierForLogging, privacy: .public)")

        let response: Components.Schemas.SuccessResponse
        do {
            response = try await api.markPostAsRead(postIds: [postId], read: true)
        } catch {
            logger.error("""
                Mark post as read failed. post=\(postIdentifierForLogging, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        await perform(with: postObjectId, type: LemmyPost.self) { post, context in
            logger.debug("Mark post as read complete. post=\(postIdentifierForLogging, privacy: .public); success=\(response.success)")
            assert(post.postInfo != nil)
            post.postInfo?.isRead = response.success

            context.saveIfNeeded()
        }
    }
}
