//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
@testable import SpudDataKit

/// A test double for `LemmyServiceType` used by `OfflineDownloadServiceTests`.
///
/// Only the two methods the offline downloader actually uses are meaningfully
/// implemented:
///
/// - `fetchFeed` seeds a batch of `post` + `page` + `pageElement` rows into the
///   injected in-memory `AppDatabase` (so the targets query and the
///   "fetchComments needs a persisted PostRecord" rule are realistic) and
///   returns the configured next-page cursor for that call.
/// - `fetchComments` records the post id it was asked for (and optionally throws
///   for a configured post id, to exercise the best-effort-per-item path).
///
/// Every other protocol member is unreachable in these tests and traps if hit.
actor RecordingLemmyService: LemmyServiceType {
    /// Per-page seeding plan for `fetchFeed`. Each call consumes the next page.
    struct Page {
        /// How many *new* posts this page inserts.
        let postCount: Int
        /// The cursor returned to the caller (nil = feed exhausted).
        let nextCursor: String?
        /// Server post ids this page re-seeds *instead of* inserting new posts —
        /// modelling a page whose posts are already in the feed (prior browsing
        /// loaded them, or Hot/Active ranking churn re-served them). The real
        /// `appendFeedPage` de-dupes these, so the persisted count does NOT grow
        /// for such a page. When non-empty, `postCount` is ignored.
        let duplicatePostIds: [Int64]

        init(postCount: Int, nextCursor: String?, duplicatePostIds: [Int64] = []) {
            self.postCount = postCount
            self.nextCursor = nextCursor
            self.duplicatePostIds = duplicatePostIds
        }
    }

    private let appDatabase: AppDatabase
    private let accountId: Int64
    private let communityId: Int64
    private let personId: Int64
    /// Image URL stamped onto every seeded post's `url` (so the post is detected
    /// as an image post and its full image becomes a download target). nil seeds
    /// text posts with no image url.
    private let imageUrlForSeededPosts: String?

    /// When set, once the planned `pages` are exhausted `fetchFeed` keeps
    /// returning this (non-nil) cursor and inserts NO new posts — modelling a
    /// pathological server that hands back a cursor forever while the persisted
    /// count plateaus. Without it, an exhausted plan returns nil (feed ended).
    private let exhaustedCursor: String?

    /// Server post ids a page may re-seed to model already-browsed / churn
    /// duplicates. A `Page` whose `duplicatePostIds` is non-empty re-inserts
    /// those exact ids (which `appendFeedPage`'s real de-dupe would drop) and
    /// inserts no *new* posts — so the persisted count doesn't grow, exactly as
    /// it wouldn't for the live importer when a page's posts are already in the
    /// feed. Tracked so the fake doesn't hand out a colliding id later.
    private var seededServerPostIds: Set<Int64> = []

    /// The seeding plan, consumed front-to-back across `fetchFeed` calls. When
    /// exhausted, further `fetchFeed` calls insert nothing and return nil.
    private var pages: [Page]
    private var pageIndex = 0
    /// Running server-post-id counter, so each seeded post is distinct. Starts
    /// at `firstServerPostId` so a test that pre-seeds "already browsed" posts
    /// can continue the id space past them and avoid colliding fresh ids.
    private var nextServerPostId: Int64
    /// Running page position for the feed's `page` rows. Starts at
    /// `firstPagePosition` so a test that pre-seeds a feed page (modelling prior
    /// browsing) can continue past it without colliding on the
    /// `(feedId, position)` unique constraint.
    private var nextPagePosition: Int64

    /// Server post ids whose `fetchComments` should throw, to exercise the
    /// best-effort-per-item path.
    private let failingCommentPostIds: Set<Int64>

    // Recorded calls.
    private(set) var fetchFeedCallCount = 0
    private(set) var fetchCommentsPostIds: [Int64] = []

    /// Fires exactly once, when `fetchFeed` is first called. Lets a test await a
    /// definite "the download has started working" signal instead of polling the
    /// call count in a bounded busy-wait (which can flake under load).
    private let firstFetchFeedStream: AsyncStream<Void>
    private let firstFetchFeedContinuation: AsyncStream<Void>.Continuation

    init(
        appDatabase: AppDatabase,
        accountId: Int64,
        communityId: Int64,
        personId: Int64,
        pages: [Page],
        imageUrlForSeededPosts: String? = "https://example.com/image.jpg",
        failingCommentPostIds: Set<Int64> = [],
        exhaustedCursor: String? = nil,
        firstServerPostId: Int64 = 1,
        firstPagePosition: Int64 = 0
    ) {
        self.appDatabase = appDatabase
        self.accountId = accountId
        self.communityId = communityId
        self.personId = personId
        self.pages = pages
        self.imageUrlForSeededPosts = imageUrlForSeededPosts
        self.failingCommentPostIds = failingCommentPostIds
        self.exhaustedCursor = exhaustedCursor
        nextServerPostId = firstServerPostId
        nextPagePosition = firstPagePosition
        (firstFetchFeedStream, firstFetchFeedContinuation) = AsyncStream<Void>.makeStream()
    }

    // MARK: - Recorded accessors

    func recordedFetchFeedCallCount() -> Int {
        fetchFeedCallCount
    }

    /// Awaitable signal that the first `fetchFeed` call has landed. A test can
    /// `await firstFetchFeedStarted()` to know the download is actually working
    /// before driving a deterministic follow-up (e.g. launching a second,
    /// rejected download), with no sleeps or bounded polling.
    func firstFetchFeedStarted() async {
        var iterator = firstFetchFeedStream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func recordedFetchCommentsPostIds() -> [Int64] {
        fetchCommentsPostIds
    }

    // MARK: - LemmyServiceType (used)

    func fetchFeed(_ feed: FeedHandle, pageCursor _: String?, showNsfw _: Bool) async throws -> String? {
        fetchFeedCallCount += 1
        if fetchFeedCallCount == 1 {
            // Signal "the download has started working" exactly once, then close
            // the stream so a waiter that arrives later still completes.
            firstFetchFeedContinuation.yield(())
            firstFetchFeedContinuation.finish()
        }

        guard pageIndex < pages.count else {
            // No more planned pages. By default the feed is exhausted (nil
            // cursor); when `exhaustedCursor` is set, keep handing back that
            // non-nil cursor and insert nothing — a server that trickles a
            // cursor forever while the persisted count plateaus.
            return exhaustedCursor
        }
        let page = pages[pageIndex]
        pageIndex += 1

        let feedKey = feed.feedKey
        let accountId = accountId
        let communityId = communityId
        let personId = personId
        let imageUrl = imageUrlForSeededPosts
        let pagePosition = nextPagePosition
        nextPagePosition += 1

        // A duplicate page re-serves posts already in the feed (prior browsing /
        // ranking churn). The real `appendFeedPage` de-dupes them, so the
        // persisted count must NOT grow: we insert no new `post` rows, only a
        // new `page` whose elements point at the EXISTING posts.
        let isDuplicatePage = !page.duplicatePostIds.isEmpty
        let postCount = isDuplicatePage ? 0 : page.postCount
        let firstServerPostId = nextServerPostId
        if !isDuplicatePage {
            nextServerPostId += Int64(postCount)
            for offset in 0..<postCount {
                seededServerPostIds.insert(firstServerPostId + Int64(offset))
            }
        }
        let duplicatePostIds = page.duplicatePostIds

        try await appDatabase.writer.write { db in
            // Lazily create the feed row on first page (mirrors appendFeedPage).
            let feedRowId: Int64
            if let existing = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM feed WHERE feedKey = ?",
                arguments: [feedKey]
            ) {
                feedRowId = existing
            } else {
                var record = FeedRecord(
                    accountId: accountId,
                    feedKey: feedKey,
                    savedOnly: false,
                    sortType: "Hot",
                    createdAt: Date()
                )
                try record.insert(db)
                feedRowId = record.id!
            }

            var pageRecord = PageRecord(feedId: feedRowId, position: pagePosition, createdAt: Date())
            try pageRecord.insert(db)
            let pageRowId = pageRecord.id!

            if isDuplicatePage {
                // Point this page's elements at the already-persisted posts; no
                // new `post` rows, so `offlineFeedPostCountSync` stays flat.
                for (offset, serverPostId) in duplicatePostIds.enumerated() {
                    let postRowId = try Int64.fetchOne(
                        db,
                        sql: "SELECT id FROM post WHERE accountId = ? AND postId = ?",
                        arguments: [accountId, serverPostId]
                    )
                    guard let postRowId else { continue }
                    var element = PageElementRecord(
                        pageId: pageRowId,
                        postId: postRowId,
                        position: Int64(offset)
                    )
                    try element.insert(db)
                }
                return
            }

            for offset in 0..<postCount {
                let serverPostId = firstServerPostId + Int64(offset)
                let now = Date()
                try db.execute(
                    sql: """
                        INSERT INTO post
                            (accountId, communityId, creatorId, postId, title, url, thumbnailUrl,
                             originalPostUrl, score, numberOfUpvotes, numberOfDownvotes, numberOfComments,
                             isRead, isSaved, isHidden, isNsfw, isRemoved, isLocked,
                             isFeaturedCommunity, isFeaturedLocal, isDeleted,
                             published, createdAt, updatedAt)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ?, ?, ?)
                        """,
                    arguments: [
                        accountId,
                        communityId,
                        personId,
                        serverPostId,
                        "Post \(serverPostId)",
                        imageUrl,
                        "https://example.com/thumb/\(serverPostId).jpg",
                        "https://example.com/post/\(serverPostId)",
                        now,
                        now,
                        now,
                    ]
                )
                let postRowId = db.lastInsertedRowID
                var element = PageElementRecord(pageId: pageRowId, postId: postRowId, position: Int64(offset))
                try element.insert(db)
            }
        }

        return page.nextCursor
    }

    func fetchComments(
        serverPostId: Components.Schemas.PostID,
        sortType _: Components.Schemas.CommentSortType
    ) async throws {
        // The API id type is Int32; the test records/configures Int64 to match
        // the DB-stored ids.
        let postId = Int64(serverPostId)
        fetchCommentsPostIds.append(postId)
        if failingCommentPostIds.contains(postId) {
            throw RecordingLemmyServiceError.commentFetchFailed
        }
    }

    // MARK: - LemmyServiceType (unused — trap if hit)

    func fetchSiteInfo() async throws {
        unreachable()
    }

    func getSiteInfo() async throws -> Components.Schemas.GetSiteResponse {
        unreachable()
    }

    func setShowNsfw(_: Bool) async throws {
        unreachable()
    }

    func setBlurNsfw(_: Bool) async throws {
        unreachable()
    }

    func setDefaultSortType(_: Components.Schemas.SortType) async throws {
        unreachable()
    }

    func saveProfile(
        displayName _: String?,
        bio _: String?,
        avatar _: String?,
        banner _: String?,
        showScores _: Bool,
        showBotAccounts _: Bool,
        showReadPosts _: Bool,
        showAvatars _: Bool,
        defaultListingType _: Components.Schemas.ListingType
    ) async throws {
        unreachable()
    }

    func fetchPersonInfo(serverPersonId _: Components.Schemas.PersonID) async throws {
        unreachable()
    }

    func fetchPersonContent(
        serverPersonId _: Components.Schemas.PersonID,
        sort _: Components.Schemas.SortType,
        page _: Int64
    ) async throws -> Components.Schemas.GetPersonDetailsResponse {
        unreachable()
    }

    func fetchCommunityInfo(serverCommunityId _: Components.Schemas.CommunityID) async throws {
        unreachable()
    }

    func fetchCommunityInfo(communityName _: String) async throws -> Components.Schemas.CommunityID {
        unreachable()
    }

    func search(
        query _: String,
        type _: Components.Schemas.SearchType,
        sort _: Components.Schemas.SortType,
        listingType _: Components.Schemas.ListingType,
        page _: Int64
    ) async throws -> Components.Schemas.SearchResponse {
        unreachable()
    }

    func listCommunities(
        type _: Components.Schemas.ListingType,
        sort _: Components.Schemas.SortType?,
        limit _: Int64?
    ) async throws -> [Components.Schemas.CommunityView] {
        unreachable()
    }

    func setSubscribed(serverCommunityId _: Components.Schemas.CommunityID, subscribed _: Bool) async throws {
        unreachable()
    }

    func vote(serverPostId _: Components.Schemas.PostID, vote _: VoteStatus.Action) async throws {
        unreachable()
    }

    func vote(serverCommentId _: Components.Schemas.CommentID, vote _: VoteStatus.Action) async throws {
        unreachable()
    }

    func createComment(
        serverPostId _: Components.Schemas.PostID,
        content _: String,
        parentCommentId _: Components.Schemas.CommentID?
    ) async throws {
        unreachable()
    }

    func createPost(
        serverCommunityId _: Components.Schemas.CommunityID,
        name _: String,
        url _: String?,
        body _: String?,
        nsfw _: Bool
    ) async throws -> Components.Schemas.PostID {
        unreachable()
    }

    func uploadImage(imageData _: Data, fileName _: String, mimeType _: String) async throws -> URL {
        unreachable()
    }

    func setSaved(serverPostId _: Components.Schemas.PostID, saved _: Bool) async throws {
        unreachable()
    }

    func setSaved(serverCommentId _: Components.Schemas.CommentID, saved _: Bool) async throws {
        unreachable()
    }

    func deleteComment(serverCommentId _: Components.Schemas.CommentID, deleted _: Bool) async throws {
        unreachable()
    }

    func deletePost(serverPostId _: Components.Schemas.PostID, deleted _: Bool) async throws {
        unreachable()
    }

    func fetchPostInfo(serverPostId _: Components.Schemas.PostID) async throws {
        unreachable()
    }

    func hidePost(serverPostId _: Components.Schemas.PostID, hidden _: Bool) async throws {
        unreachable()
    }

    func outboxFailureEvents() async -> AsyncStream<OutboxFailure> {
        AsyncStream { $0.finish() }
    }

    func drainPendingOutbox() async {
        unreachable()
    }

    func saveDraft(_: OutboundDraftInput) async throws -> String {
        unreachable()
    }

    func submitDraft(clientToken _: String) async {
        unreachable()
    }

    func retryComposition(clientToken _: String) async {
        unreachable()
    }

    func discardComposition(clientToken _: String) async {
        unreachable()
    }

    func loadDraft(draftKey _: String) async throws -> OutboundContentRecord? {
        unreachable()
    }

    func saveDirectMessageDraft(body _: String, recipientServerPersonId _: Int64) async throws -> String {
        unreachable()
    }

    func sendDirectMessage(body _: String, recipientServerPersonId _: Int64) async throws -> String {
        unreachable()
    }

    func applyOptimisticPostEdit(
        serverPostId _: Components.Schemas.PostID,
        title _: String,
        body _: String?,
        url _: String?,
        nsfw _: Bool
    ) async {
        unreachable()
    }

    func composerFailureEvents() async -> AsyncStream<ComposerOutboxFailure> {
        AsyncStream { $0.finish() }
    }

    func composerSuccessEvents() async -> AsyncStream<ComposerOutboxSuccess> {
        AsyncStream { $0.finish() }
    }

    func markAsRead(serverPostId _: Components.Schemas.PostID) async throws {
        unreachable()
    }

    func fetchReplies(unreadOnly _: Bool, page _: Int64) async throws -> Components.Schemas.GetRepliesResponse {
        unreachable()
    }

    func fetchMentions(unreadOnly _: Bool, page _: Int64) async throws -> Components.Schemas.GetPersonMentionsResponse {
        unreachable()
    }

    func fetchPrivateMessages(unreadOnly _: Bool, page _: Int64) async throws -> Components.Schemas.PrivateMessagesResponse {
        unreachable()
    }

    func unreadCount() async throws -> UnreadCount {
        unreachable()
    }

    func markReplyAsRead(commentReplyId _: Components.Schemas.CommentReplyID, read _: Bool) async throws {
        unreachable()
    }

    func markMentionAsRead(personMentionId _: Components.Schemas.PersonMentionID, read _: Bool) async throws {
        unreachable()
    }

    func markPrivateMessageAsRead(privateMessageId _: Components.Schemas.PrivateMessageID, read _: Bool) async throws {
        unreachable()
    }

    func markAllInboxAsRead() async throws {
        unreachable()
    }

    func sendPrivateMessage(
        content _: String,
        recipientId _: Components.Schemas.PersonID
    ) async throws -> Components.Schemas.PrivateMessageView {
        unreachable()
    }

    func setBlocked(serverPersonId _: Components.Schemas.PersonID, blocked _: Bool) async throws {
        unreachable()
    }

    func setBlocked(serverCommunityId _: Components.Schemas.CommunityID, blocked _: Bool) async throws {
        unreachable()
    }

    func reportPost(serverPostId _: Components.Schemas.PostID, reason _: String) async throws {
        unreachable()
    }

    func reportComment(serverCommentId _: Components.Schemas.CommentID, reason _: String) async throws {
        unreachable()
    }

    func fetchBlockedList() async throws -> BlockedList {
        unreachable()
    }

    func fetchModerationCapability() async throws -> ModerationCapability {
        unreachable()
    }

    func removePost(serverPostId _: Components.Schemas.PostID, removed _: Bool, reason _: String?) async throws {
        unreachable()
    }

    func lockPost(serverPostId _: Components.Schemas.PostID, locked _: Bool) async throws {
        unreachable()
    }

    func featurePost(serverPostId _: Components.Schemas.PostID, featured _: Bool, local _: Bool) async throws {
        unreachable()
    }

    func removeComment(serverCommentId _: Components.Schemas.CommentID, removed _: Bool, reason _: String?) async throws {
        unreachable()
    }

    func distinguishComment(serverCommentId _: Components.Schemas.CommentID, distinguished _: Bool) async throws {
        unreachable()
    }

    func banFromCommunity(
        serverCommunityId _: Components.Schemas.CommunityID,
        serverPersonId _: Components.Schemas.PersonID,
        ban _: Bool,
        removeData _: Bool,
        reason _: String?
    ) async throws {
        unreachable()
    }

    func resolveObject(query _: String) async throws -> ResolvedLemmyObject {
        unreachable()
    }
}

enum RecordingLemmyServiceError: Error {
    case commentFetchFailed
}

/// Traps a call to an unused fake method with a clear message instead of
/// returning a bogus value.
private func unreachable(_ function: StaticString = #function) -> Never {
    fatalError("RecordingLemmyService.\(function) is not implemented for OfflineDownloadServiceTests")
}
