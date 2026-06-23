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

    /// The operation requires a signed-in account, but this service is
    /// backed by a signed-out account.
    case requiresAuthentication

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

    /// Fetch a person's profile together with one page of their posts and
    /// comments. The `person_view` is mirrored into the database (so the
    /// profile header can be observed like any other person), while the posts
    /// and comments are returned transiently - a snapshot of the requested
    /// page rather than rows in a persistent feed, mirroring how `search`
    /// returns its results. Navigation from a result uses the server-side ids
    /// carried in the response, which the id-based screens resolve on their
    /// own. Works for both signed-in and signed-out accounts.
    func fetchPersonContent(
        serverPersonId: Components.Schemas.PersonID,
        sort: Components.Schemas.SortType,
        page: Int64
    ) async throws -> Components.Schemas.GetPersonDetailsResponse

    /// Fetch the full community info (header fields, counts, subscribed state)
    /// for `serverCommunityId` and mirror it into the database. Used to
    /// populate the community screen for communities the account hasn't cached.
    func fetchCommunityInfo(
        serverCommunityId: Components.Schemas.CommunityID
    ) async throws

    /// Fetch the full community info by name (`gnome` for a local community or
    /// `worldnews@lemmy.world` for a remote one) and mirror it into the
    /// database. Returns the resolved server-side community id.
    @discardableResult
    func fetchCommunityInfo(
        communityName: String
    ) async throws -> Components.Schemas.CommunityID

    /// Run a search against the backing instance and return the decoded
    /// results. Search results are transient (a snapshot of what matched the
    /// query right now), so they are returned directly rather than mirrored
    /// into the persistent feed. Navigation from a result uses the server-side
    /// ids carried in the response, which the id-based screens resolve on
    /// their own. Works for both signed-in and signed-out accounts.
    func search(
        query: String,
        type: Components.Schemas.SearchType,
        sort: Components.Schemas.SortType,
        listingType: Components.Schemas.ListingType,
        page: Int64
    ) async throws -> Components.Schemas.SearchResponse

    /// Subscribe to or unsubscribe from `serverCommunityId` for the backing
    /// account. Throws `LemmyServiceError.requiresAuthentication` if this
    /// service is backed by a signed-out account.
    func setSubscribed(
        serverCommunityId: Components.Schemas.CommunityID,
        subscribed: Bool
    ) async throws

    func vote(
        serverPostId: Components.Schemas.PostID,
        vote action: VoteStatus.Action
    ) async throws

    func vote(
        serverCommentId: Components.Schemas.CommentID,
        vote action: VoteStatus.Action
    ) async throws

    /// Create a new comment on `serverPostId`. Pass `parentCommentId` to
    /// reply to an existing comment, or `nil` to reply to the post itself.
    /// Throws `LemmyServiceError.requiresAuthentication` if this service is
    /// backed by a signed-out account.
    func createComment(
        serverPostId: Components.Schemas.PostID,
        content: String,
        parentCommentId: Components.Schemas.CommentID?
    ) async throws

    /// Create a new post in `serverCommunityId` and mirror the returned
    /// `PostView` into the persistent store so it shows up immediately.
    /// Returns the new post's server id for navigation. Throws
    /// `LemmyServiceError.requiresAuthentication` when signed out.
    @discardableResult
    func createPost(
        serverCommunityId: Components.Schemas.CommunityID,
        name: String,
        url: String?,
        body: String?,
        nsfw: Bool
    ) async throws -> Components.Schemas.PostID

    /// Upload an image to the backing instance's pict-rs and return the
    /// fully-qualified image url. Transient (not mirrored). Throws
    /// `LemmyServiceError.requiresAuthentication` when signed out.
    func uploadImage(
        imageData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> URL

    /// Save or unsave `serverPostId` for the backing account. Throws
    /// `LemmyServiceError.requiresAuthentication` if this service is backed
    /// by a signed-out account.
    func setSaved(
        serverPostId: Components.Schemas.PostID,
        saved: Bool
    ) async throws

    /// Save or unsave `serverCommentId` for the backing account. Throws
    /// `LemmyServiceError.requiresAuthentication` if this service is backed
    /// by a signed-out account.
    func setSaved(
        serverCommentId: Components.Schemas.CommentID,
        saved: Bool
    ) async throws

    func fetchPostInfo(
        serverPostId: Components.Schemas.PostID
    ) async throws

    /// Hide or unhide `serverPostId` for the backing account. Hidden posts are
    /// dropped from feed lists. Throws `LemmyServiceError.requiresAuthentication`
    /// if this service is backed by a signed-out account.
    func hidePost(
        serverPostId: Components.Schemas.PostID,
        hidden: Bool
    ) async throws

    /// A stream of permanent outbox failures (e.g. an expired session) for the
    /// vote/save/hide operations enqueued through this service. Each event names
    /// the entity whose optimistic write was rolled back so the UI can surface
    /// the failure. Transient failures (offline / server hiccups) are retried
    /// silently and never appear here.
    func outboxFailureEvents() async -> AsyncStream<OutboxFailure>

    /// Drains any operations persisted in this account's outbox right now (e.g.
    /// ops left pending by a previous session, or held while offline). Lazily
    /// constructs and `start()`s the outbox if needed. A no-op when the account
    /// row can't be resolved.
    func drainPendingOutbox() async

    func markAsRead(
        serverPostId: Components.Schemas.PostID
    ) async throws

    // MARK: Inbox

    /// Fetch one page of inbox replies. Results are transient (returned to the
    /// caller, like `search`) rather than mirrored into the persistent store.
    /// Throws `LemmyServiceError.requiresAuthentication` when signed out.
    func fetchReplies(
        unreadOnly: Bool,
        page: Int64
    ) async throws -> Components.Schemas.GetRepliesResponse

    /// Fetch one page of inbox mentions. Transient, like `fetchReplies`.
    func fetchMentions(
        unreadOnly: Bool,
        page: Int64
    ) async throws -> Components.Schemas.GetPersonMentionsResponse

    /// Fetch one page of private messages. Transient, like `fetchReplies`.
    func fetchPrivateMessages(
        unreadOnly: Bool,
        page: Int64
    ) async throws -> Components.Schemas.PrivateMessagesResponse

    /// Fetch the count of unread replies, mentions, and private messages.
    /// Throws `LemmyServiceError.requiresAuthentication` when signed out.
    func unreadCount() async throws -> UnreadCount

    /// Mark a single comment reply as read/unread.
    func markReplyAsRead(
        commentReplyId: Components.Schemas.CommentReplyID,
        read: Bool
    ) async throws

    /// Mark a single person mention as read/unread.
    func markMentionAsRead(
        personMentionId: Components.Schemas.PersonMentionID,
        read: Bool
    ) async throws

    /// Mark a single private message as read/unread.
    func markPrivateMessageAsRead(
        privateMessageId: Components.Schemas.PrivateMessageID,
        read: Bool
    ) async throws

    /// Mark all inbox items (replies + mentions + private messages) as read.
    func markAllInboxAsRead() async throws

    /// Send a private message to `recipientId` and return the created view.
    /// Throws `LemmyServiceError.requiresAuthentication` when signed out.
    @discardableResult
    func sendPrivateMessage(
        content: String,
        recipientId: Components.Schemas.PersonID
    ) async throws -> Components.Schemas.PrivateMessageView

    // MARK: Safety (block / report)

    /// Block or unblock the person `serverPersonId` for the backing account.
    /// On success the returned `PersonView` is mirrored into the store; the
    /// server filters blocked authors out of subsequent feed fetches, so the
    /// caller should refresh the current feed to make blocked content
    /// disappear. Throws `LemmyServiceError.requiresAuthentication` when signed
    /// out.
    func setBlocked(
        serverPersonId: Components.Schemas.PersonID,
        blocked: Bool
    ) async throws

    /// Block or unblock the community `serverCommunityId` for the backing
    /// account. On success the returned `CommunityView` is mirrored into the
    /// store; the server filters blocked communities out of subsequent feed
    /// fetches, so the caller should refresh the current feed. Throws
    /// `LemmyServiceError.requiresAuthentication` when signed out.
    func setBlocked(
        serverCommunityId: Components.Schemas.CommunityID,
        blocked: Bool
    ) async throws

    /// Report `serverPostId` with the given `reason`. Transient (not mirrored).
    /// Throws `LemmyServiceError.requiresAuthentication` when signed out.
    func reportPost(
        serverPostId: Components.Schemas.PostID,
        reason: String
    ) async throws

    /// Report `serverCommentId` with the given `reason`. Transient (not
    /// mirrored). Throws `LemmyServiceError.requiresAuthentication` when signed
    /// out.
    func reportComment(
        serverCommentId: Components.Schemas.CommentID,
        reason: String
    ) async throws

    /// Fetch the account's current block lists from the server (via
    /// `getSite` → `my_user`). Transient (returned to the caller, like
    /// `search`) so the settings screen always reflects server truth. Throws
    /// `LemmyServiceError.requiresAuthentication` when signed out.
    func fetchBlockedList() async throws -> BlockedList

    // MARK: Moderation

    /// Fetch the account's moderation capability from the server (via
    /// `getSite` → `my_user`): the set of communities it moderates plus
    /// whether it is a site admin. Transient (returned to the caller, like
    /// `fetchBlockedList`), so mod UI always reflects server truth. A
    /// signed-out account resolves to `.none` rather than throwing, so the
    /// caller can gate UI uniformly without branching on auth state.
    func fetchModerationCapability() async throws -> ModerationCapability

    /// Remove (or restore) `serverPostId` as a moderator/admin. On success the
    /// updated `PostView` is mirrored into the store. Throws
    /// `LemmyServiceError.requiresAuthentication` when signed out.
    func removePost(
        serverPostId: Components.Schemas.PostID,
        removed: Bool,
        reason: String?
    ) async throws

    /// Lock (or unlock) `serverPostId` as a moderator/admin. Mirrors the
    /// updated `PostView`. Throws `.requiresAuthentication` when signed out.
    func lockPost(
        serverPostId: Components.Schemas.PostID,
        locked: Bool
    ) async throws

    /// Feature (pin) or unfeature `serverPostId`. `local` pins to the instance
    /// front page (admin-only); otherwise pins to the community. Mirrors the
    /// updated `PostView`. Throws `.requiresAuthentication` when signed out.
    func featurePost(
        serverPostId: Components.Schemas.PostID,
        featured: Bool,
        local: Bool
    ) async throws

    /// Remove (or restore) `serverCommentId` as a moderator/admin. Mirrors the
    /// updated `CommentView`. Throws `.requiresAuthentication` when signed out.
    func removeComment(
        serverCommentId: Components.Schemas.CommentID,
        removed: Bool,
        reason: String?
    ) async throws

    /// Distinguish (or undistinguish) `serverCommentId`. Mirrors the updated
    /// `CommentView`. Throws `.requiresAuthentication` when signed out.
    func distinguishComment(
        serverCommentId: Components.Schemas.CommentID,
        distinguished: Bool
    ) async throws

    /// Ban (or unban) `serverPersonId` from `serverCommunityId`. When banning,
    /// `removeData` also removes the person's existing content in the
    /// community. Mirrors the updated `PersonView`. Transient otherwise. Throws
    /// `.requiresAuthentication` when signed out.
    func banFromCommunity(
        serverCommunityId: Components.Schemas.CommunityID,
        serverPersonId: Components.Schemas.PersonID,
        ban: Bool,
        removeData: Bool,
        reason: String?
    ) async throws

    /// Resolves a federated object (post, community, person, or comment) by its
    /// canonical URL, under this service's account. Comments resolve to
    /// `.comment` (deferred); unrecognised input resolves to `.unresolved`.
    func resolveObject(query: String) async throws -> ResolvedLemmyObject
}

/// The current account's moderation capability, decoded from `getSite` →
/// `my_user`: the communities it moderates and whether it is a site admin. A
/// small Sendable value type so it can flow from the `LemmyService` actor to
/// the main-actor UI that gates mod controls.
public struct ModerationCapability: Sendable, Equatable {
    /// Server-side ids of the communities the account moderates.
    public let moderatedCommunityIds: Set<Components.Schemas.CommunityID>
    /// Whether the account is a site admin (can moderate anywhere and feature
    /// posts to the instance front page).
    public let isAdmin: Bool

    public init(
        moderatedCommunityIds: Set<Components.Schemas.CommunityID>,
        isAdmin: Bool
    ) {
        self.moderatedCommunityIds = moderatedCommunityIds
        self.isAdmin = isAdmin
    }

    /// No moderation powers. The resolved capability for a signed-out account
    /// or an account that moderates nothing and is not an admin.
    public static let none = ModerationCapability(moderatedCommunityIds: [], isAdmin: false)

    /// Whether the account can take moderator actions in `communityId` -
    /// either because it moderates that community or because it is a site
    /// admin (admins can moderate everywhere).
    public func canModerate(communityId: Components.Schemas.CommunityID) -> Bool {
        isAdmin || moderatedCommunityIds.contains(communityId)
    }

    /// Whether any moderation surface should be offered at all.
    public var hasAnyPower: Bool {
        isAdmin || !moderatedCommunityIds.isEmpty
    }
}

/// The account's current block lists, decoded from `getSite` → `my_user`.
/// A small Sendable value type so it can flow from the `LemmyService` actor to
/// the main-actor settings screen.
public struct BlockedList: Sendable, Equatable {
    public struct Person: Sendable, Equatable, Identifiable {
        public let serverPersonId: Components.Schemas.PersonID
        public let name: String
        /// `@user@instance`-style handle for display.
        public let handle: String
        public let avatarUrl: URL?

        public var id: Components.Schemas.PersonID {
            serverPersonId
        }
    }

    public struct Community: Sendable, Equatable, Identifiable {
        public let serverCommunityId: Components.Schemas.CommunityID
        public let name: String
        /// `community@instance`-style handle for display.
        public let handle: String
        public let iconUrl: URL?

        public var id: Components.Schemas.CommunityID {
            serverCommunityId
        }
    }

    public let persons: [Person]
    public let communities: [Community]

    public init(persons: [Person], communities: [Community]) {
        self.persons = persons
        self.communities = communities
    }

    public static let empty = BlockedList(persons: [], communities: [])
}

/// The count of unread inbox items, split by kind. A small Sendable value type
/// so it can flow from the `LemmyService` actor to the main-actor badge.
public struct UnreadCount: Sendable, Equatable {
    public let replies: Int
    public let mentions: Int
    public let privateMessages: Int

    public init(replies: Int, mentions: Int, privateMessages: Int) {
        self.replies = replies
        self.mentions = mentions
        self.privateMessages = privateMessages
    }

    public static let zero = UnreadCount(replies: 0, mentions: 0, privateMessages: 0)

    /// Total across all kinds; drives the tab badge.
    public var total: Int {
        replies + mentions + privateMessages
    }
}

public actor LemmyService: LemmyServiceType {
    // MARK: Public

    let accountIdentifierForLogging: String

    // MARK: Private

    let accountIsSignedOut: Bool
    let appDatabase: AppDatabase
    let api: LemmyApi
    private let reachability: ReachabilityMonitoring

    /// Task-memoized lazy outbox. Construction is deferred to the first
    /// vote/save/hide call because it needs `accountSiteIds()` (an async DB
    /// read) and must call `start()`. Memoizing the *Task* (not the value)
    /// makes concurrent callers share one construction even under actor
    /// reentrancy: the `outboxTask = task` assignment runs before the first
    /// `await task.value`, so a second caller arriving mid-await sees the
    /// in-flight task rather than starting a second drain loop.
    private var outboxTask: Task<OutboxService?, Never>?

    // MARK: Functions

    init(
        accountKeychainId: String,
        accountIsSignedOut: Bool,
        appDatabase: AppDatabase,
        api: LemmyApi,
        reachability: ReachabilityMonitoring
    ) {
        accountIdentifierForLogging = accountKeychainId
        self.accountIsSignedOut = accountIsSignedOut
        self.appDatabase = appDatabase
        self.api = api
        self.reachability = reachability

        logger.info("Creating new service for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))")
    }

    /// Lazily builds (and `start()`s) the per-account `OutboxService`, returning
    /// `nil` only when the account row can't be resolved (no ids -> no outbox).
    /// Memoized via `outboxTask` so every call shares one service instance.
    private func outboxService() async -> OutboxService? {
        if let outboxTask { return await outboxTask.value }
        let task = Task<OutboxService?, Never> { [self] in
            guard let ids = try? await accountSiteIds() else { return nil }
            let performer = LemmyOutboxPerformer(
                api: api,
                appDatabase: appDatabase,
                accountId: ids.0,
                siteId: ids.1
            )
            let service = OutboxService(
                accountId: ids.0,
                appDatabase: appDatabase,
                performer: performer,
                reachability: reachability,
                now: { Date().timeIntervalSince1970 }
            )
            await service.start()
            return service
        }
        outboxTask = task
        let result = await task.value
        if result == nil { outboxTask = nil } // allow retry after a transient failure; keep memoized only on success
        return result
    }

    /// Looks up the GRDB account row for this LemmyService and returns
    /// `(accountRowId, siteRowId)` - both are needed as foreign keys when
    /// upserting posts/comments/communities.
    func accountSiteIds() async throws -> (Int64, Int64)? {
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

            case let .saved(sortType):
                guard !accountIsSignedOut else {
                    throw LemmyServiceError.requiresAuthentication
                }
                logger.debug("""
                    Fetch saved feed for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                    feedId=\(feedKey, privacy: .public) \
                    sortType=\(sortType.rawValue, privacy: .public) \
                    pageCursor=\(pageCursor ?? "nil", privacy: .public)
                    """)
                response = try await api.getPosts(
                    type: .All,
                    sort: sortType,
                    filter: .saved,
                    page: pageCursor
                )
            }
        } catch let error as LemmyServiceError {
            throw error
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

        try await mirrorFeedPageToAppDatabase(
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
    ) async throws {
        guard let (accountRowId, siteRowId) = try await accountSiteIds() else {
            throw LemmyServiceError.internalInconsistency(
                description: "Feed page not persisted: no account/site row for keychainId"
            )
        }
        try await appDatabase.appendFeedPage(
            feedKey: feedKey,
            feedType: feedType,
            accountId: accountRowId,
            siteId: siteRowId,
            posts: posts
        )
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

        try await mirrorCommentsToAppDatabase(
            serverPostId: serverPostId,
            sortType: sortType,
            comments: response.comments
        )

        // A removed comment carries no reason in the comment object — fetch it
        // from the public modlog, but only when there's something to explain.
        if response.comments.contains(where: \.comment.removed) {
            await mirrorCommentRemovalReasons(serverPostId: serverPostId)
        }
    }

    /// Fetches moderator removal reasons for the post's removed comments from
    /// the public modlog and mirrors them. Best-effort: a failure here must not
    /// break comment loading.
    private func mirrorCommentRemovalReasons(serverPostId: Components.Schemas.PostID) async {
        do {
            guard let (accountRowId, _) = try await accountSiteIds() else { return }

            let modlog = try await api.getModlog(
                postID: serverPostId,
                type: .ModRemoveComment
            )
            let reasons = Self.removalReasons(from: modlog.removed_comments)

            try await appDatabase.mirrorCommentRemovalReasons(
                forServerPostId: Int64(serverPostId),
                accountId: accountRowId,
                reasonsByServerCommentId: reasons
            )
        } catch {
            logger.error("Fetch comment removal reasons failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Builds a `serverCommentId -> reason` map from modlog comment-removal
    /// entries. The modlog is newest-first, so the first entry seen per comment
    /// is the most recent removal; restores (`removed == false`) and empty
    /// reasons are skipped.
    static func removalReasons(
        from removedComments: [Components.Schemas.ModRemoveCommentView]
    ) -> [Int64: String] {
        var reasons: [Int64: String] = [:]
        for view in removedComments {
            let entry = view.mod_remove_comment
            guard entry.removed, let reason = entry.reason, !reason.isEmpty else { continue }
            let commentId = Int64(entry.comment_id)
            if reasons[commentId] == nil {
                reasons[commentId] = reason
            }
        }
        return reasons
    }

    private func mirrorCommentsToAppDatabase(
        serverPostId: Components.Schemas.PostID,
        sortType: Components.Schemas.CommentSortType,
        comments: [Components.Schemas.CommentView]
    ) async throws {
        guard let (accountRowId, siteRowId) = try await accountSiteIds() else {
            throw LemmyServiceError.internalInconsistency(
                description: "mirrorCommentsToAppDatabase: account/site not found for \(accountIdentifierForLogging)"
            )
        }
        try await appDatabase.upsertComments(
            forServerPostId: Int64(serverPostId),
            accountId: accountRowId,
            siteId: siteRowId,
            sortType: sortType,
            comments: comments
        )
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
            response = try await api.getPersonDetails(personID: serverPersonId)
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

        let resolvedInstanceActorId = await appDatabase.accountInstanceActorId(
            forKeychainId: accountIdentifierForLogging
        )
        guard let resolvedInstanceActorId,
              appDatabase.personRowIdSync(
                  instanceActorId: resolvedInstanceActorId,
                  personId: Int64(serverPersonId)
              ) != nil
        else {
            throw LemmyServiceError.internalInconsistency(
                description: "fetchPersonInfo: person row not persisted after mirror for personId=\(serverPersonId)"
            )
        }
    }

    public func fetchPersonContent(
        serverPersonId: Components.Schemas.PersonID,
        sort: Components.Schemas.SortType,
        page: Int64
    ) async throws -> Components.Schemas.GetPersonDetailsResponse {
        logger.debug("""
            Fetch person content. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            personId=\(serverPersonId, privacy: .public) sort=\(sort.rawValue, privacy: .public) \
            page=\(page, privacy: .public)
            """)

        let response: Components.Schemas.GetPersonDetailsResponse
        do {
            response = try await api.getPersonDetails(
                personID: serverPersonId,
                sort: sort,
                page: page
            )
        } catch {
            logger.error("""
                Fetch person content failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                personId=\(serverPersonId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        // Mirror the profile so the header can be observed like any other
        // person; the posts/comments stay transient (returned to the caller).
        await mirrorPersonInfoToAppDatabase(personView: response.person_view)

        return response
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

    public func fetchCommunityInfo(
        serverCommunityId: Components.Schemas.CommunityID
    ) async throws {
        logger.debug("""
            Fetch community info. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            communityId=\(serverCommunityId, privacy: .public)
            """)

        let response: Components.Schemas.GetCommunityResponse
        do {
            response = try await api.getCommunity(communityID: serverCommunityId)
        } catch {
            logger.error("""
                Fetch community info failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                communityId=\(serverCommunityId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        await mirrorCommunityInfoToAppDatabase(view: response.community_view)
    }

    @discardableResult
    public func fetchCommunityInfo(
        communityName: String
    ) async throws -> Components.Schemas.CommunityID {
        logger.debug("""
            Fetch community info. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            communityName=\(communityName, privacy: .public)
            """)

        let response: Components.Schemas.GetCommunityResponse
        do {
            response = try await api.getCommunity(name: communityName)
        } catch {
            logger.error("""
                Fetch community info failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                communityName=\(communityName, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        await mirrorCommunityInfoToAppDatabase(view: response.community_view)

        return response.community_view.community.id
    }

    public func resolveObject(query: String) async throws -> ResolvedLemmyObject {
        let response = try await api.resolveObject(query: query)
        // Resolve under the current account, so the returned ids are local to
        // this account's home instance. Use the async read (not the *Sync
        // variant) so we don't block the actor's executor.
        let rawActorId = await appDatabase.accountInstanceActorId(forKeychainId: accountIdentifierForLogging)
        let homeInstance = rawActorId.flatMap { InstanceActorId(from: $0) } ?? .invalid
        if !homeInstance.isValid {
            logger.warning("resolveObject: could not resolve a home instance for the current account; resolved ids will carry an invalid instance")
        }
        return ResolvedLemmyObject(response: response, homeInstance: homeInstance)
    }

    public func search(
        query: String,
        type: Components.Schemas.SearchType,
        sort: Components.Schemas.SortType,
        listingType: Components.Schemas.ListingType,
        page: Int64
    ) async throws -> Components.Schemas.SearchResponse {
        logger.debug("""
            Search. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            query=\(query, privacy: .private) type=\(type.rawValue, privacy: .public) \
            sort=\(sort.rawValue, privacy: .public) listingType=\(listingType.rawValue, privacy: .public) \
            page=\(page, privacy: .public)
            """)

        let response: Components.Schemas.SearchResponse
        do {
            response = try await api.search(
                query: query,
                type: type,
                sort: sort,
                listingType: listingType,
                page: page
            )
        } catch {
            logger.error("""
                Search failed. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                type=\(type.rawValue, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        return response
    }

    public func setSubscribed(
        serverCommunityId: Components.Schemas.CommunityID,
        subscribed: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Set subscribed rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                communityId=\(serverCommunityId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Set subscribed=\(subscribed, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            communityId=\(serverCommunityId, privacy: .public)
            """)

        let response: Components.Schemas.CommunityResponse
        do {
            response = try await api.followCommunity(communityID: serverCommunityId, follow: subscribed)
        } catch {
            logger.error("""
                Set subscribed failed. communityId=\(serverCommunityId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        await mirrorCommunityInfoToAppDatabase(view: response.community_view)
    }

    private func mirrorCommunityInfoToAppDatabase(
        view: Components.Schemas.CommunityView
    ) async {
        do {
            guard let (accountRowId, _) = try await accountSiteIds() else { return }
            try await appDatabase.upsertCommunity(from: view, accountId: accountRowId)
        } catch {
            logger.error("AppDatabase upsertCommunity failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func vote(
        serverPostId: Components.Schemas.PostID,
        vote action: VoteStatus.Action
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Vote rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                postId=\(serverPostId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

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

        let desired = currentVoteStatus.effectiveAction(for: action)

        logger.debug("""
            Vote '\(action, privacy: .public)' \
            (desired '\(desired, privacy: .public)') \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        guard let outbox = await outboxService() else {
            throw LemmyServiceError.internalInconsistency(description: "outbox unavailable")
        }
        await outbox.enqueue(OutboxOperation(
            entityType: .post,
            entityServerId: Int64(serverPostId),
            desiredState: .vote(desired)
        ))
    }

    public func vote(
        serverCommentId: Components.Schemas.CommentID,
        vote action: VoteStatus.Action
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Vote rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                commentId=\(serverCommentId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

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

        let desired = currentVoteStatus.effectiveAction(for: action)

        logger.debug("""
            Vote '\(action, privacy: .public)' \
            (desired '\(desired, privacy: .public)') \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            commentId=\(serverCommentId, privacy: .public)
            """)

        guard let outbox = await outboxService() else {
            throw LemmyServiceError.internalInconsistency(description: "outbox unavailable")
        }
        await outbox.enqueue(OutboxOperation(
            entityType: .comment,
            entityServerId: Int64(serverCommentId),
            desiredState: .vote(desired)
        ))
    }

    public func createComment(
        serverPostId: Components.Schemas.PostID,
        content: String,
        parentCommentId: Components.Schemas.CommentID?
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Create comment rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                postId=\(serverPostId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Create comment for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public) \
            parentCommentId=\(parentCommentId.map(String.init) ?? "nil", privacy: .public)
            """)

        let response: Components.Schemas.CommentResponse
        do {
            response = try await api.createComment(
                postID: serverPostId,
                content: content,
                parentID: parentCommentId
            )
        } catch {
            logger.error("""
                Create comment failed. postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        await mirrorCommentToAppDatabase(view: response.comment_view)
    }

    @discardableResult
    public func createPost(
        serverCommunityId: Components.Schemas.CommunityID,
        name: String,
        url: String?,
        body: String?,
        nsfw: Bool
    ) async throws -> Components.Schemas.PostID {
        guard !accountIsSignedOut else {
            logger.debug("""
                Create post rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                communityId=\(serverCommunityId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Create post for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            communityId=\(serverCommunityId, privacy: .public)
            """)

        let response: Components.Schemas.PostResponse
        do {
            response = try await api.createPost(
                communityID: serverCommunityId,
                name: name,
                url: url,
                body: body,
                nsfw: nsfw
            )
        } catch {
            logger.error("""
                Create post failed. communityId=\(serverCommunityId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        await mirrorPostInfoToAppDatabase(view: response.post_view)
        return response.post_view.post.id
    }

    public func uploadImage(
        imageData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> URL {
        guard !accountIsSignedOut else {
            logger.debug("""
                Image upload rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Upload image for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            bytes=\(imageData.count, privacy: .public)
            """)

        let uploaded: LemmyApi.UploadedImage
        do {
            uploaded = try await api.uploadImage(
                imageData: imageData,
                fileName: fileName,
                mimeType: mimeType
            )
        } catch {
            logger.error("""
                Image upload failed. \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        return uploaded.url
    }

    public func setSaved(
        serverPostId: Components.Schemas.PostID,
        saved: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Save post rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                postId=\(serverPostId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Set saved=\(saved, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        guard let outbox = await outboxService() else {
            throw LemmyServiceError.internalInconsistency(description: "outbox unavailable")
        }
        await outbox.enqueue(OutboxOperation(
            entityType: .post,
            entityServerId: Int64(serverPostId),
            desiredState: .save(saved)
        ))
    }

    public func setSaved(
        serverCommentId: Components.Schemas.CommentID,
        saved: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Save comment rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                commentId=\(serverCommentId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Set saved=\(saved, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            commentId=\(serverCommentId, privacy: .public)
            """)

        guard let outbox = await outboxService() else {
            throw LemmyServiceError.internalInconsistency(description: "outbox unavailable")
        }
        await outbox.enqueue(OutboxOperation(
            entityType: .comment,
            entityServerId: Int64(serverCommentId),
            desiredState: .save(saved)
        ))
    }

    func mirrorCommentToAppDatabase(
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

    // MARK: Safety (block / report)

    public func setBlocked(
        serverPersonId: Components.Schemas.PersonID,
        blocked: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Block person rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                personId=\(serverPersonId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Set blocked=\(blocked, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            personId=\(serverPersonId, privacy: .public)
            """)

        let response: Components.Schemas.BlockPersonResponse
        do {
            response = try await api.blockPerson(personID: serverPersonId, block: blocked)
        } catch {
            logger.error("""
                Block person failed. personId=\(serverPersonId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        // Mirror the refreshed author info. The server now filters this author's
        // content out of subsequent feed fetches; the caller refreshes the feed.
        await mirrorPersonInfoToAppDatabase(view: response.person_view)
    }

    public func setBlocked(
        serverCommunityId: Components.Schemas.CommunityID,
        blocked: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Block community rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                communityId=\(serverCommunityId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Set blocked=\(blocked, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            communityId=\(serverCommunityId, privacy: .public)
            """)

        let response: Components.Schemas.BlockCommunityResponse
        do {
            response = try await api.blockCommunity(communityID: serverCommunityId, block: blocked)
        } catch {
            logger.error("""
                Block community failed. communityId=\(serverCommunityId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        // Mirror the refreshed community info. The server now filters this
        // community's content out of subsequent feed fetches; the caller
        // refreshes the feed.
        await mirrorCommunityInfoToAppDatabase(view: response.community_view)
    }

    func mirrorPersonInfoToAppDatabase(
        view: Components.Schemas.PersonView
    ) async {
        do {
            guard let (_, siteRowId) = try await accountSiteIds() else { return }
            try await appDatabase.upsertPerson(from: view, siteId: siteRowId)
        } catch {
            logger.error("AppDatabase upsertPerson failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func reportPost(
        serverPostId: Components.Schemas.PostID,
        reason: String
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Report post rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                postId=\(serverPostId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Report post for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        do {
            _ = try await api.createPostReport(postID: serverPostId, reason: reason)
        } catch {
            logger.error("""
                Report post failed. postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    public func reportComment(
        serverCommentId: Components.Schemas.CommentID,
        reason: String
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Report comment rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                commentId=\(serverCommentId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Report comment for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            commentId=\(serverCommentId, privacy: .public)
            """)

        do {
            _ = try await api.createCommentReport(commentID: serverCommentId, reason: reason)
        } catch {
            logger.error("""
                Report comment failed. commentId=\(serverCommentId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    public func fetchBlockedList() async throws -> BlockedList {
        guard !accountIsSignedOut else {
            logger.debug("""
                Fetch blocked list rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("Fetch blocked list for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))")

        let response: Components.Schemas.GetSiteResponse
        do {
            response = try await api.getSite()
        } catch {
            logger.error("""
                Fetch blocked list failed. \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        guard let myUser = response.my_user else {
            return .empty
        }

        let persons = myUser.person_blocks.map { block -> BlockedList.Person in
            let target = block.target
            return BlockedList.Person(
                serverPersonId: target.id,
                name: target.name,
                handle: Self.handle(name: target.name, actorId: target.actor_id),
                avatarUrl: target.avatar.flatMap(URL.init(string:))
            )
        }

        let communities = myUser.community_blocks.map { block -> BlockedList.Community in
            let community = block.community
            return BlockedList.Community(
                serverCommunityId: community.id,
                name: community.name,
                handle: Self.handle(name: community.name, actorId: community.actor_id),
                iconUrl: community.icon.flatMap(URL.init(string:))
            )
        }

        return BlockedList(persons: persons, communities: communities)
    }

    /// Builds a `name@instance` handle from a bare name and the federated
    /// `actor_id` url (e.g. `https://lemmy.world/u/alice` -> `alice@lemmy.world`).
    /// Falls back to the bare name if the host can't be resolved.
    private static func handle(name: String, actorId: String) -> String {
        guard
            let url = URL(string: actorId),
            let host = url.host
        else {
            return name
        }
        return "\(name)@\(host)"
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

        guard appDatabase.postRowIdSync(
            forKeychainId: accountIdentifierForLogging,
            serverPostId: Int64(serverPostId)
        ) != nil else {
            throw LemmyServiceError.internalInconsistency(
                description: "fetchPostInfo: post row not persisted after mirror for postId=\(serverPostId)"
            )
        }
    }

    func mirrorPostInfoToAppDatabase(
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

    public func hidePost(
        serverPostId: Components.Schemas.PostID,
        hidden: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Hide post rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                postId=\(serverPostId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Set hidden=\(hidden, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        guard let outbox = await outboxService() else {
            throw LemmyServiceError.internalInconsistency(description: "outbox unavailable")
        }
        await outbox.enqueue(OutboxOperation(
            entityType: .post,
            entityServerId: Int64(serverPostId),
            desiredState: .hide(hidden)
        ))
    }

    public func outboxFailureEvents() async -> AsyncStream<OutboxFailure> {
        guard let outbox = await outboxService() else {
            return AsyncStream { $0.finish() }
        }
        return await outbox.failureEvents
    }

    public func drainPendingOutbox() async {
        await outboxService()?.drainAll()
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
            response = try await api.markPostAsRead(postIDs: [serverPostId], read: true)
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

    // MARK: Inbox

    public func fetchReplies(
        unreadOnly: Bool,
        page: Int64
    ) async throws -> Components.Schemas.GetRepliesResponse {
        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Fetch inbox replies. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            unreadOnly=\(unreadOnly, privacy: .public) page=\(page, privacy: .public)
            """)

        do {
            return try await api.getReplies(
                commentSort: .New,
                unreadOnly: unreadOnly,
                page: page
            )
        } catch {
            logger.error("""
                Fetch inbox replies failed. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    public func fetchMentions(
        unreadOnly: Bool,
        page: Int64
    ) async throws -> Components.Schemas.GetPersonMentionsResponse {
        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Fetch inbox mentions. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            unreadOnly=\(unreadOnly, privacy: .public) page=\(page, privacy: .public)
            """)

        do {
            return try await api.getPersonMentions(
                commentSort: .New,
                unreadOnly: unreadOnly,
                page: page
            )
        } catch {
            logger.error("""
                Fetch inbox mentions failed. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    public func fetchPrivateMessages(
        unreadOnly: Bool,
        page: Int64
    ) async throws -> Components.Schemas.PrivateMessagesResponse {
        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Fetch private messages. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            unreadOnly=\(unreadOnly, privacy: .public) page=\(page, privacy: .public)
            """)

        do {
            return try await api.getPrivateMessages(
                unreadOnly: unreadOnly,
                page: page
            )
        } catch {
            logger.error("""
                Fetch private messages failed. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    public func unreadCount() async throws -> UnreadCount {
        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        let response: Components.Schemas.GetUnreadCountResponse
        do {
            response = try await api.getUnreadCount()
        } catch {
            logger.error("""
                Fetch unread count failed. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        return UnreadCount(
            replies: Int(response.replies),
            mentions: Int(response.mentions),
            privateMessages: Int(response.private_messages)
        )
    }

    public func markReplyAsRead(
        commentReplyId: Components.Schemas.CommentReplyID,
        read: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Mark reply as read. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            commentReplyId=\(commentReplyId, privacy: .public) read=\(read, privacy: .public)
            """)

        do {
            try await api.markCommentReplyAsRead(commentReplyID: commentReplyId, read: read)
        } catch {
            logger.error("""
                Mark reply as read failed. commentReplyId=\(commentReplyId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    public func markMentionAsRead(
        personMentionId: Components.Schemas.PersonMentionID,
        read: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Mark mention as read. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            personMentionId=\(personMentionId, privacy: .public) read=\(read, privacy: .public)
            """)

        do {
            try await api.markPersonMentionAsRead(personMentionID: personMentionId, read: read)
        } catch {
            logger.error("""
                Mark mention as read failed. personMentionId=\(personMentionId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    public func markPrivateMessageAsRead(
        privateMessageId: Components.Schemas.PrivateMessageID,
        read: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Mark private message as read. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            privateMessageId=\(privateMessageId, privacy: .public) read=\(read, privacy: .public)
            """)

        do {
            try await api.markPrivateMessageAsRead(privateMessageID: privateMessageId, read: read)
        } catch {
            logger.error("""
                Mark private message as read failed. privateMessageId=\(privateMessageId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    public func markAllInboxAsRead() async throws {
        guard !accountIsSignedOut else {
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Mark all inbox as read. \
            account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
            """)

        // Lemmy's markAllAsRead only covers replies + mentions; private
        // messages must be marked individually. Fetch the unread messages and
        // mark each, then call markAllAsRead for the comment-based items.
        do {
            let unreadMessages = try await api.getPrivateMessages(unreadOnly: true, page: 1)
            for view in unreadMessages.private_messages where !view.private_message.read {
                _ = try? await api.markPrivateMessageAsRead(
                    privateMessageID: view.private_message.id,
                    read: true
                )
            }
        } catch {
            logger.error("""
                Mark all inbox (private messages) failed. \
                \(String(describing: error), privacy: .public)
                """)
            // Non-fatal: still attempt to clear replies/mentions below.
        }

        do {
            _ = try await api.markAllAsRead()
        } catch {
            logger.error("""
                Mark all inbox (replies/mentions) failed. \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    @discardableResult
    public func sendPrivateMessage(
        content: String,
        recipientId: Components.Schemas.PersonID
    ) async throws -> Components.Schemas.PrivateMessageView {
        guard !accountIsSignedOut else {
            logger.debug("""
                Send private message rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                recipientId=\(recipientId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Send private message. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            recipientId=\(recipientId, privacy: .public)
            """)

        let response: Components.Schemas.PrivateMessageResponse
        do {
            response = try await api.createPrivateMessage(content: content, recipientID: recipientId)
        } catch {
            logger.error("""
                Send private message failed. recipientId=\(recipientId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        return response.private_message_view
    }
}
