//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog

private let logger = Logger.appDatabase

/// Coarse load state for the authored side of the activity stream, surfaced
/// separately from the items so a degraded (offline) authored fetch never fails
/// the whole stream.
public enum ActivityLoadState: Sendable, Equatable {
    /// No authored fetch in flight; more authored pages may be available.
    case idle
    /// An authored page fetch is in flight.
    case loading
    /// Every enabled authored source is exhausted (or authored content is
    /// disabled) - there is nothing more to page.
    case complete
    /// The last authored fetch failed. The local stream keeps flowing; a retry
    /// via `loadMore()` may recover.
    case degraded
}

/// Produces the full unified activity timeline for one account: the reactive
/// local stream (read / seen / saved / hidden / voted) interleaved with the
/// account holder's authored posts and comments, reverse-chronological by
/// `occurredAt`, with bounded pagination.
///
/// ## Sources
/// - **Local** - `AppDatabase.observeLocalActivity`, reactive and *complete*
///   (re-emits on any DB change; returns the full set, nothing older pending).
/// - **Authored posts** - `AppDatabase.observePersonPostListRows`, reactive;
///   the rows are persisted by the authored-page fetch and rendered live (vote /
///   save state). The merge frontier for posts is driven by the fetch responses,
///   not the observation.
/// - **Authored comments** - transient, accumulated page by page from the
///   injected ``AuthoredActivitySource`` (which wraps `getPersonDetails`).
///
/// ## Bounded merge
/// The emitted prefix is clamped to the merge frontier (see ``ActivityMerge``):
/// the oldest `occurredAt` complete across every still-paginating authored
/// source. `loadMore()` fetches exactly one more authored page, lowering the
/// frontier so the prefix grows - it never "fetches everything".
///
/// ## Filters / offline
/// When neither `.post` nor `.comment` is enabled, the authored fetch is skipped
/// entirely (a pure local, offline-friendly stream). An authored fetch failure
/// degrades to ``ActivityLoadState/degraded`` and keeps emitting the local items
/// rather than failing the stream.
public actor ActivityCoordinator {
    // MARK: Dependencies

    private let appDatabase: AppDatabase
    private let authoredSource: AuthoredActivitySource?
    private let personRowId: Int64?

    // MARK: Configuration (set when the stream starts)

    private var accountId: Int64 = 0
    private var filters: Set<ActivityFilterType> = []
    private var searchQuery: String?
    /// Authored-post fetching is possible: `.post` is on, a source exists, and the
    /// account's own person row is known (needed for the post observation).
    private var postsEnabled = false
    /// Authored-comment fetching is possible: `.comment` is on and a source exists.
    private var commentsEnabled = false

    // MARK: Buffers

    private var localItems: [ActivityItem] = []
    private var authoredPostItems: [ActivityItem] = []
    private var authoredCommentItems: [ActivityItem] = []

    // MARK: Pagination bookkeeping

    /// Bumped on every (re)subscription. Captured by `loadMore` before its network
    /// await so a fetch that was already in flight when the stream was reset
    /// resolves into a no-op instead of corrupting the new subscription's state.
    private var streamGeneration: UInt64 = 0

    private var nextPage: Int64 = 1
    private var isFetching = false
    private var postsExhausted = false
    private var commentsExhausted = false
    private var postsLoadedOnce = false
    private var commentsLoadedOnce = false
    /// Oldest authored-post `published` loaded so far (the post frontier), or nil
    /// before the first page lands / once the source is exhausted.
    private var postsOldestLoaded: Date?
    /// Oldest authored-comment `published` loaded so far.
    private var commentsOldestLoaded: Date?

    public private(set) var loadState: ActivityLoadState = .idle

    // MARK: Output

    private var itemsContinuation: AsyncStream<[ActivityItem]>.Continuation?
    private var stateContinuation: AsyncStream<ActivityLoadState>.Continuation?
    /// Last array yielded, so identical re-computations (e.g. a no-op DB change)
    /// don't spam the consumer.
    private var lastEmitted: [ActivityItem]?

    private var localTask: Task<Void, Never>?
    private var postsTask: Task<Void, Never>?

    public init(
        appDatabase: AppDatabase,
        personRowId: Int64?,
        authoredSource: AuthoredActivitySource?
    ) {
        self.appDatabase = appDatabase
        self.personRowId = personRowId
        self.authoredSource = authoredSource
    }

    // MARK: - Public API

    /// Starts (or restarts) the unified timeline for `accountId` under `filters`
    /// and `searchQuery`, returning the items stream. Re-subscribing tears down
    /// any previous subscription first.
    ///
    /// The first authored page (when authored content is enabled) is fetched
    /// automatically so content appears without an initial scroll; until it
    /// lands, the local items are shown unclamped (offline-friendly), so the
    /// list may settle once the first page arrives. Use ``loadMore()`` to extend.
    public func activityStream(
        accountId: Int64,
        filters: Set<ActivityFilterType>,
        searchQuery: String?
    ) -> AsyncStream<[ActivityItem]> {
        stopStreaming()
        resetState()

        self.accountId = accountId
        self.filters = filters
        let trimmed = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.searchQuery = (trimmed?.isEmpty ?? true) ? nil : trimmed
        postsEnabled = filters.contains(.post) && authoredSource != nil && personRowId != nil
        commentsEnabled = filters.contains(.comment) && authoredSource != nil

        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            let setup = Task { await self.beginStreaming(continuation: continuation) }
            continuation.onTermination = { _ in
                setup.cancel()
                Task { await self.stopStreaming() }
            }
        }
    }

    /// A stream of authored load-state transitions (idle / loading / complete /
    /// degraded). Replays the current state on subscribe.
    public func statusStream() -> AsyncStream<ActivityLoadState> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            let setup = Task { await self.registerStateContinuation(continuation) }
            continuation.onTermination = { [weak self] _ in
                setup.cancel()
                Task { await self?.clearStateContinuation() }
            }
        }
    }

    /// Fetches the next authored page (posts + comments come from one
    /// `getPersonDetails` call), advancing the merge frontier by exactly one page.
    /// A no-op when authored content is disabled, a fetch is already in flight, or
    /// every enabled authored source is exhausted.
    public func loadMore() async {
        guard let authoredSource else { return }
        guard postsEnabled || commentsEnabled else { return }
        guard !isFetching else { return }

        let postsActive = postsEnabled && !postsExhausted
        let commentsActive = commentsEnabled && !commentsExhausted
        guard postsActive || commentsActive else {
            setState(.complete)
            return
        }

        isFetching = true
        setState(.loading)
        let page = nextPage
        let generation = streamGeneration

        do {
            let result = try await authoredSource.loadPage(page)
            // The stream was reset (re-subscribe / account switch) while this fetch
            // was in flight: drop the result so it can't write into the new
            // subscription's buffers, frontier, or page cursor.
            guard generation == streamGeneration else { return }
            ingest(page: result)
            nextPage += 1
            isFetching = false
            let exhausted = (!postsEnabled || postsExhausted) && (!commentsEnabled || commentsExhausted)
            setState(exhausted ? .complete : .idle)
            emit()
        } catch {
            guard generation == streamGeneration else { return }
            isFetching = false
            logger.error("""
                Authored activity page \(page, privacy: .public) failed: \
                \(String(describing: error), privacy: .public)
                """)
            // Degrade, don't fail: keep the page cursor put (so a retry re-fetches
            // the same page) and keep emitting the local + already-loaded authored.
            setState(.degraded)
            emit()
        }
    }

    // MARK: - Streaming lifecycle

    private func beginStreaming(continuation: AsyncStream<[ActivityItem]>.Continuation) {
        itemsContinuation = continuation
        startLocalObservation()
        startPostsObservation()
        if postsEnabled || commentsEnabled {
            Task { await self.loadMore() }
        }
    }

    private func registerStateContinuation(_ continuation: AsyncStream<ActivityLoadState>.Continuation) {
        // End any prior status subscriber cleanly so a re-subscribe doesn't leave
        // it hanging on a continuation that will never finish.
        stateContinuation?.finish()
        stateContinuation = continuation
        continuation.yield(loadState)
    }

    private func clearStateContinuation() {
        stateContinuation = nil
    }

    private func stopStreaming() {
        localTask?.cancel()
        localTask = nil
        postsTask?.cancel()
        postsTask = nil
        // Finish any prior items subscription so a re-subscribe (new filters)
        // cleanly ends the old stream instead of leaving its consumer hanging.
        itemsContinuation?.finish()
        itemsContinuation = nil
    }

    private func resetState() {
        streamGeneration &+= 1
        localItems = []
        authoredPostItems = []
        authoredCommentItems = []
        nextPage = 1
        isFetching = false
        postsExhausted = false
        commentsExhausted = false
        postsLoadedOnce = false
        commentsLoadedOnce = false
        postsOldestLoaded = nil
        commentsOldestLoaded = nil
        loadState = .idle
        lastEmitted = nil
    }

    // MARK: - Observations

    private func startLocalObservation() {
        let stream = appDatabase.observeLocalActivity(
            accountId: accountId,
            filters: filters,
            searchQuery: searchQuery
        )
        localTask = Task { [weak self] in
            for await items in stream {
                if Task.isCancelled { break }
                await self?.ingestLocal(items)
            }
        }
    }

    private func startPostsObservation() {
        guard postsEnabled, let personRowId else { return }
        let stream = appDatabase.observePersonPostListRows(
            personRowId: personRowId,
            accountId: accountId,
            sort: .New
        )
        let query = searchQuery
        postsTask = Task { [weak self] in
            for await rows in stream {
                if Task.isCancelled { break }
                let items = rows
                    .map(ActivityItem.init(authoredPost:))
                    .filter { Self.matches($0, query: query) }
                await self?.ingestPosts(items)
            }
        }
    }

    private func ingestLocal(_ items: [ActivityItem]) {
        localItems = items
        emit()
    }

    private func ingestPosts(_ items: [ActivityItem]) {
        authoredPostItems = items
        emit()
    }

    private func ingest(page result: AuthoredActivityPage) {
        if postsEnabled {
            if result.postsExhausted {
                postsExhausted = true
            } else {
                postsLoadedOnce = true
                postsOldestLoaded = Self.olderOf(postsOldestLoaded, result.oldestPostPublished)
            }
        }
        if commentsEnabled {
            if result.commentsExhausted {
                commentsExhausted = true
            } else {
                commentsLoadedOnce = true
                commentsOldestLoaded = Self.olderOf(commentsOldestLoaded, result.oldestCommentPublished)
                let filtered = result.comments.filter { Self.matches($0, query: searchQuery) }
                authoredCommentItems.append(contentsOf: filtered)
            }
        }
    }

    // MARK: - Emit

    private func emit() {
        // Authored content is shown only once its first page has resolved (or the
        // source is known-empty): before that the frontier is unknown, so showing
        // it would let a later page reorder it.
        let posts = (postsEnabled && (postsLoadedOnce || postsExhausted)) ? authoredPostItems : []
        let comments = (commentsEnabled && (commentsLoadedOnce || commentsExhausted)) ? authoredCommentItems : []

        let merged = ActivityMerge.merge(
            local: localItems,
            authoredPosts: posts,
            authoredComments: comments,
            frontier: currentFrontier()
        )

        guard merged != lastEmitted else { return }
        lastEmitted = merged
        itemsContinuation?.yield(merged)
    }

    /// The merge frontier: the `max` of the oldest-loaded timestamps across every
    /// still-paginating authored source. A source contributes only while it is
    /// enabled, has loaded at least one page, and is not exhausted - so before the
    /// first page (or once exhausted, or when authored content is disabled) it
    /// imposes no clamp and the local stream shows in full.
    private func currentFrontier() -> Date? {
        var contributions: [Date?] = []
        if postsEnabled, !postsExhausted, postsLoadedOnce {
            contributions.append(postsOldestLoaded)
        }
        if commentsEnabled, !commentsExhausted, commentsLoadedOnce {
            contributions.append(commentsOldestLoaded)
        }
        return ActivityMerge.frontier(contributions)
    }

    private func setState(_ state: ActivityLoadState) {
        loadState = state
        stateContinuation?.yield(state)
    }

    // MARK: - Helpers

    /// Older (smaller) of two optional dates, treating nil as "no value".
    private static func olderOf(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (nil, nil): nil
        case let (value?, nil): value
        case let (nil, value?): value
        case let (a?, b?): min(a, b)
        }
    }

    /// Client-side search match for authored items (`getPersonDetails` has no
    /// server search). Matches a post title or a comment body / parent-post title.
    /// v1: the frontier is still computed from the unfiltered page timestamps, so
    /// search does not change pagination boundaries.
    private static func matches(_ item: ActivityItem, query: String?) -> Bool {
        guard let query, !query.isEmpty else { return true }
        let needle = query.lowercased()
        switch item.object {
        case let .post(row):
            return row.title.lowercased().contains(needle)
        case let .comment(row):
            return row.body.lowercased().contains(needle)
                || row.parentPostTitle.lowercased().contains(needle)
        }
    }
}
