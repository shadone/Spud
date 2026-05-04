//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
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
    /// Fetch one page of posts for `feed`. Pass `pageCursor: nil` for the
    /// first page; on subsequent calls pass the cursor returned by the
    /// previous fetch. Returns the cursor for the next page, or nil if the
    /// feed is exhausted.
    @discardableResult
    func fetchFeed(_ feed: FeedHandle, pageCursor: String?) async throws -> String?

    func fetchComments(
        serverPostId: Components.Schemas.PostID,
        sortType: Components.Schemas.CommentSortType
    ) async throws

    func fetchSiteInfo() async throws

    func fetchPersonInfo(
        serverPersonId: Components.Schemas.PersonID
    ) async throws

    func vote(
        serverPostId: Components.Schemas.PostID,
        vote action: VoteStatus.Action
    ) async throws

    func vote(
        serverCommentId: Components.Schemas.CommentID,
        vote action: VoteStatus.Action
    ) async throws

    func fetchPostInfo(
        serverPostId: Components.Schemas.PostID
    ) async throws

    func markAsRead(
        serverPostId: Components.Schemas.PostID
    ) async throws
}

public actor LemmyService: LemmyServiceType {
    // MARK: Public

    let accountIdentifierForLogging: String

    // MARK: Private

    private let accountIsSignedOut: Bool
    let appDatabase: AppDatabase
    private let api: LemmyApi

    // MARK: Functions

    init(
        accountKeychainId: String,
        accountIsSignedOut: Bool,
        appDatabase: AppDatabase,
        api: LemmyApi
    ) {
        accountIdentifierForLogging = accountKeychainId
        self.accountIsSignedOut = accountIsSignedOut
        self.appDatabase = appDatabase
        self.api = api

        logger.info("Creating new service for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))")
    }

    /// Looks up the GRDB account row for this LemmyService and returns
    /// `(accountRowId, siteRowId)` - both are needed as foreign keys when
    /// upserting posts/comments/communities.
    private func accountSiteIds() async throws -> (Int64, Int64)? {
        try await appDatabase.writer.read { db in
            guard
                let account = try AccountRecord
                .filter(Column("accountKeychainId") == self.accountIdentifierForLogging)
                .fetchOne(db)
            else {
                return nil
            }
            return (account.id!, account.siteId)
        }
    }

    public func fetchFeed(_ feed: FeedHandle, pageCursor: String?) async throws -> String? {
        let feedKey = feed.feedKey
        let feedType = feed.feedType

        let response: Components.Schemas.GetPostsResponse
        do {
            switch feedType {
            case let .frontpage(listingType, sortType):
                logger.debug("""
                    Fetch feed for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                    feedId=\(feedKey, privacy: .public) \
                    listingType=\(listingType.rawValue, privacy: .public) \
                    sortType=\(sortType.rawValue, privacy: .public) \
                    pageCursor=\(pageCursor ?? "nil", privacy: .public)
                    """)
                response = try await api.getPosts(
                    type: listingType,
                    sort: sortType,
                    page: pageCursor
                )

            case let .community(communityName, instance, sortType):
                logger.debug("""
                    Fetch feed for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                    feedId=\(feedKey, privacy: .public) \
                    communityName=\(communityName, privacy: .public) \
                    instance=\(instance.debugDescription, privacy: .public) \
                    sortType=\(sortType.rawValue, privacy: .public) \
                    pageCursor=\(pageCursor ?? "nil", privacy: .public)
                    """)
                response = try await api.getPosts(
                    community: .name("\(communityName)@\(instance.hostWithPort)"),
                    sort: sortType,
                    page: pageCursor
                )
            }
        } catch {
            logger.error("""
                Fetch feed failed. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                feedId=\(feedKey, privacy: .public) \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("""
            Fetch feed complete with \(response.posts.count, privacy: .public) posts. \
            account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            feedId=\(feedKey, privacy: .public)
            """)

        await mirrorFeedPageToAppDatabase(
            feedKey: feedKey,
            feedType: feedType,
            posts: response.posts
        )

        return response.next_page
    }

    private func mirrorFeedPageToAppDatabase(
        feedKey: String,
        feedType: FeedType,
        posts: [Components.Schemas.PostView]
    ) async {
        do {
            guard let (accountRowId, siteRowId) = try await accountSiteIds() else {
                return
            }
            try await appDatabase.appendFeedPage(
                feedKey: feedKey,
                feedType: feedType,
                accountId: accountRowId,
                siteId: siteRowId,
                posts: posts
            )
        } catch {
            logger.error("AppDatabase appendFeedPage failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func fetchComments(
        serverPostId: Components.Schemas.PostID,
        sortType: Components.Schemas.CommentSortType
    ) async throws {
        logger.debug("""
            Fetch comments for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
            postId=\(serverPostId, privacy: .public) \
            sortType=\(sortType.rawValue, privacy: .public)
            """)

        let response: Components.Schemas.GetCommentsResponse
        do {
            response = try await api.getComments(
                postID: serverPostId,
                sort: sortType,
                maxDepth: 8
            )
        } catch {
            logger.error("""
                Fetch comments failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("""
            Fetch comments for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            complete with \(response.comments.count, privacy: .public) comments
            """)

        await mirrorCommentsToAppDatabase(
            serverPostId: serverPostId,
            sortType: sortType,
            comments: response.comments
        )
    }

    private func mirrorCommentsToAppDatabase(
        serverPostId: Components.Schemas.PostID,
        sortType: Components.Schemas.CommentSortType,
        comments: [Components.Schemas.CommentView]
    ) async {
        do {
            guard let (accountRowId, siteRowId) = try await accountSiteIds() else {
                return
            }
            try await appDatabase.upsertComments(
                forServerPostId: Int64(serverPostId),
                accountId: accountRowId,
                siteId: siteRowId,
                sortType: sortType,
                comments: comments
            )
        } catch {
            logger.error("AppDatabase upsertComments failed: \(String(describing: error), privacy: .public)")
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

        do {
            let (_, siteId) = try await appDatabase.upsertSite(from: response)
            let accountId = try await appDatabase.upsertAccount(
                keychainId: accountIdentifierForLogging,
                isSignedOut: accountIsSignedOut,
                siteId: siteId,
                myUser: response.my_user
            )
            if let follows = response.my_user?.follows {
                try await appDatabase.setFollowedCommunities(
                    accountId: accountId,
                    follows: follows
                )
            }
        } catch {
            logger.error("AppDatabase fetchSiteInfo upsert failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func fetchPersonInfo(
        serverPersonId: Components.Schemas.PersonID
    ) async throws {
        logger.debug("""
            Fetch person info. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            personId=\(serverPersonId, privacy: .public)
            """)

        let response: Components.Schemas.GetPersonDetailsResponse
        do {
            response = try await api.getPersonDetails(personId: serverPersonId)
        } catch {
            logger.error("""
                Fetch person info failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                personId=\(serverPersonId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("""
            Fetch person info complete. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            personId=\(serverPersonId, privacy: .public)
            """)

        await mirrorPersonInfoToAppDatabase(personView: response.person_view)
    }

    private func mirrorPersonInfoToAppDatabase(
        personView: Components.Schemas.PersonView
    ) async {
        do {
            guard let (_, siteId) = try await accountSiteIds() else { return }
            try await appDatabase.upsertPerson(from: personView, siteId: siteId)
        } catch {
            logger.error("Failed to mirror person info to AppDatabase: \(String(describing: error), privacy: .public)")
        }
    }

    public func vote(
        serverPostId: Components.Schemas.PostID,
        vote action: VoteStatus.Action
    ) async throws {
        let currentVoteStatus: VoteStatus
        do {
            currentVoteStatus = try await appDatabase.postVoteStatus(
                forAccountKeychainId: accountIdentifierForLogging,
                serverPostId: serverPostId
            )
        } catch {
            logger.error("Failed to read post vote status: \(String(describing: error), privacy: .public)")
            throw LemmyServiceError.internalInconsistency(description: "post vote status lookup failed: \(error.localizedDescription)")
        }

        let effectiveAction = currentVoteStatus.effectiveAction(for: action)

        logger.debug("""
            Vote '\(action, privacy: .public)' \
            (effective '\(effectiveAction, privacy: .public)') \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        let response: Components.Schemas.PostResponse
        do {
            response = try await api.likePost(serverPostId, status: effectiveAction)
        } catch {
            logger.error("""
                Vote failed. postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        await mirrorPostInfoToAppDatabase(view: response.post_view)
    }

    public func vote(
        serverCommentId: Components.Schemas.CommentID,
        vote action: VoteStatus.Action
    ) async throws {
        let currentVoteStatus: VoteStatus
        do {
            currentVoteStatus = try await appDatabase.commentVoteStatus(
                forAccountKeychainId: accountIdentifierForLogging,
                serverCommentId: serverCommentId
            )
        } catch {
            logger.error("Failed to read comment vote status: \(String(describing: error), privacy: .public)")
            throw LemmyServiceError.internalInconsistency(description: "comment vote status lookup failed: \(error.localizedDescription)")
        }

        let effectiveAction = currentVoteStatus.effectiveAction(for: action)

        logger.debug("""
            Vote '\(action, privacy: .public)' \
            (effective '\(effectiveAction, privacy: .public)') \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            commentId=\(serverCommentId, privacy: .public)
            """)

        let response: Components.Schemas.CommentResponse
        do {
            response = try await api.likeComment(serverCommentId, status: effectiveAction)
        } catch {
            logger.error("""
                Vote failed. commentId=\(serverCommentId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        await mirrorCommentVoteToAppDatabase(view: response.comment_view)
    }

    private func mirrorCommentVoteToAppDatabase(
        view: Components.Schemas.CommentView
    ) async {
        do {
            guard let (accountRowId, siteRowId) = try await accountSiteIds() else {
                return
            }
            try await appDatabase.upsertComment(
                from: view,
                accountId: accountRowId,
                siteId: siteRowId
            )
        } catch {
            logger.error("AppDatabase upsertComment failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func fetchPostInfo(
        serverPostId: Components.Schemas.PostID
    ) async throws {
        logger.debug("""
            Fetch post. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        let response: Components.Schemas.GetPostResponse
        do {
            response = try await api.getPost(id: serverPostId)
        } catch {
            logger.error("""
                Fetch post failed. postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("""
            Fetch post complete. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        await mirrorPostInfoToAppDatabase(view: response.post_view)
    }

    private func mirrorPostInfoToAppDatabase(
        view: Components.Schemas.PostView
    ) async {
        do {
            guard let (accountRowId, siteRowId) = try await accountSiteIds() else {
                return
            }
            try await appDatabase.upsertPost(
                from: view,
                accountId: accountRowId,
                siteId: siteRowId
            )
        } catch {
            logger.error("AppDatabase upsertPost failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func markAsRead(
        serverPostId: Components.Schemas.PostID
    ) async throws {
        logger.debug("""
            Marking post as read. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        let response: Components.Schemas.SuccessResponse
        do {
            response = try await api.markPostAsRead(postIds: [serverPostId], read: true)
        } catch {
            logger.error("""
                Mark post as read failed. postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        logger.debug("""
            Mark post as read complete. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public) success=\(response.success, privacy: .public)
            """)

        if response.success {
            do {
                guard let (accountRowId, _) = try await accountSiteIds() else { return }
                try await appDatabase.setPostIsRead(
                    accountId: accountRowId,
                    serverPostId: Int64(serverPostId),
                    isRead: true
                )
            } catch {
                logger.error("AppDatabase setPostIsRead failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
