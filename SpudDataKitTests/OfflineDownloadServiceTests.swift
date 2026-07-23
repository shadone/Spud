//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import Testing
@testable import SpudDataKit

/// Tests for `OfflineDownloadService` — the SpudDataKit engine that
/// predownloads a feed (pages + comment trees + images) for offline browsing.
///
/// Each test seeds the minimal account graph directly into an in-memory
/// database, then drives the service with a `RecordingLemmyService` (whose
/// `fetchFeed` seeds posts into that same DB) and a `RecordingImageService`.
struct OfflineDownloadServiceTests {
    private let appDatabase: AppDatabase
    private let accountId: Int64
    private let siteId: Int64
    private let communityId: Int64
    private let personId: Int64

    private let feed = FeedHandle(
        feedKey: "feed-1",
        feedType: .frontpage(listingType: .All, sortType: .Hot)
    )
    private let commentSort = Lemmy.CommentSortType.Hot

    init() async throws {
        appDatabase = try AppDatabase.inMemory()
        let seeded = try await Self.seedGraph(appDatabase)
        accountId = seeded.accountId
        siteId = seeded.siteId
        communityId = seeded.communityId
        personId = seeded.personId
    }

    // MARK: - Seed

    private static func seedGraph(
        _ appDatabase: AppDatabase
    ) async throws -> (accountId: Int64, siteId: Int64, communityId: Int64, personId: Int64) {
        let now = Date()
        return try await appDatabase.writer.write { db in
            try db.execute(
                sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)",
                arguments: ["https://test.instance", now]
            )
            let instanceId = db.lastInsertedRowID
            try db.execute(
                sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)",
                arguments: [instanceId, now, now]
            )
            let siteId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO account
                        (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                    VALUES (?, 'kc-1', 1, 0, 0, ?, ?)
                    """,
                arguments: [siteId, now, now]
            )
            let accountId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO person
                        (siteId, personId, isAdmin, isBanned, isBotAccount, isDeleted, isLocal,
                         numberOfPosts, numberOfComments, createdAt, updatedAt)
                    VALUES (?, 1, 0, 0, 0, 0, 1, 0, 0, ?, ?)
                    """,
                arguments: [siteId, now, now]
            )
            let personId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO community
                        (accountId, communityId, isHidden, isLocal, isNsfw, isPostingRestrictedToMods,
                         isRemoved, subscribedState, numberOfSubscribers, numberOfPosts,
                         numberOfComments, createdAt, updatedAt)
                    VALUES (?, 1, 0, 1, 0, 0, 0, 'NotSubscribed', 0, 0, 0, ?, ?)
                    """,
                arguments: [accountId, now, now]
            )
            let communityId = db.lastInsertedRowID
            return (accountId, siteId, communityId, personId)
        }
    }

    private func makeLemmy(
        pages: [RecordingLemmyService.Page],
        imageUrlForSeededPosts: String? = "https://example.com/image.jpg",
        failingCommentPostIds: Set<Int64> = [],
        partialCommentPostIds: Set<Int64> = [],
        partialCommentReason: CommentFetchCompletion.PartialReason = .pageBudgetExhausted,
        exhaustedCursor: String? = nil,
        firstServerPostId: Int64 = 1,
        firstPagePosition: Int64 = 0
    ) -> RecordingLemmyService {
        RecordingLemmyService(
            appDatabase: appDatabase,
            accountId: accountId,
            communityId: communityId,
            personId: personId,
            pages: pages,
            imageUrlForSeededPosts: imageUrlForSeededPosts,
            failingCommentPostIds: failingCommentPostIds,
            partialCommentPostIds: partialCommentPostIds,
            partialCommentReason: partialCommentReason,
            exhaustedCursor: exhaustedCursor,
            firstServerPostId: firstServerPostId,
            firstPagePosition: firstPagePosition
        )
    }

    /// Drives a download to completion, collecting every emitted progress value.
    /// `maxPosts` defaults to the service default (100) but is overridable so a
    /// test can assert a custom cap is honored.
    private func runDownload(
        service: OfflineDownloadService,
        lemmy: RecordingLemmyService,
        showNsfw: Bool = false,
        maxPosts: Int = OfflineDownloadService.defaultMaxPosts
    ) async -> [OfflineDownloadProgress] {
        var collected: [OfflineDownloadProgress] = []
        for await progress in service.download(
            feed: feed,
            lemmyService: lemmy,
            accountId: accountId,
            siteId: siteId,
            commentSort: commentSort,
            showNsfw: showNsfw,
            maxPosts: maxPosts
        ) {
            collected.append(progress)
        }
        return collected
    }

    // MARK: - Seed helpers

    /// Directly seed `count` posts into the feed (one page), modelling posts the
    /// user already loaded by browsing BEFORE tapping Download. Returns the
    /// server post ids seeded (1...count), so a later `fetchFeed` page can
    /// re-serve them as duplicates. The `RecordingLemmyService` is created with a
    /// `nextServerPostId` that continues past these so its fresh pages never
    /// collide.
    private func preSeedBrowsedPosts(count: Int) async throws -> [Int64] {
        let ids = Array(Int64(1)...Int64(count))
        let feedKey = feed.feedKey
        let accountId = accountId
        let communityId = communityId
        let personId = personId
        try await appDatabase.writer.write { db in
            var feedRecord = FeedRecord(
                accountId: accountId,
                feedKey: feedKey,
                savedOnly: false,
                sortType: "Hot",
                createdAt: Date()
            )
            try feedRecord.insert(db)
            let feedRowId = feedRecord.id!
            var pageRecord = PageRecord(feedId: feedRowId, position: 0, createdAt: Date())
            try pageRecord.insert(db)
            let pageRowId = pageRecord.id!
            for (offset, serverPostId) in ids.enumerated() {
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
                        "https://example.com/image.jpg",
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
        return ids
    }

    // MARK: - Tests

    /// Three pages of 30 posts each (90) plus a fourth that would push past 100:
    /// the loop must stop once the persisted count reaches the 100 cap rather
    /// than draining the cursor forever.
    @Test
    func pageLoopStopsAtMaxPosts() async throws {
        let lemmy = makeLemmy(pages: [
            .init(postCount: 30, nextCursor: "p2"),
            .init(postCount: 30, nextCursor: "p3"),
            .init(postCount: 30, nextCursor: "p4"),
            .init(postCount: 30, nextCursor: "p5"),
            .init(postCount: 30, nextCursor: "p6"),
        ])
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: RecordingImageService(), diagnostics: DiagnosticLogSpy(), pacing: .immediate())

        let progress = await runDownload(service: service, lemmy: lemmy)

        // 30+30+30 = 90 < 100, fourth page -> 120 >= 100, so it stops after 4 calls.
        let calls = await lemmy.recordedFetchFeedCallCount()
        #expect(calls == 4, "should stop paging once persisted count reaches the 100 cap")

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished)
        // totalPosts is capped at the default maxPosts even though 120 posts
        // were persisted.
        #expect(terminal.totalPosts == OfflineDownloadService.defaultMaxPosts)
    }

    /// A custom cap (40) must limit BOTH the page loop and the targets: with
    /// 30-post pages, the loop stops after the second page (60 >= 40) and the
    /// content phase processes only the 40 capped targets, not all 60 persisted.
    @Test
    func customMaxPostsLimitsPagesAndTargets() async throws {
        let lemmy = makeLemmy(pages: [
            .init(postCount: 30, nextCursor: "p2"),
            .init(postCount: 30, nextCursor: "p3"),
            .init(postCount: 30, nextCursor: "p4"),
        ])
        let imageService = RecordingImageService()
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: imageService, diagnostics: DiagnosticLogSpy(), pacing: .immediate())

        let progress = await runDownload(service: service, lemmy: lemmy, maxPosts: 40)

        // 30 < 40, second page -> 60 >= 40, so it stops after 2 fetchFeed calls
        // (the custom cap, not the 100 default, governs the page loop).
        let calls = await lemmy.recordedFetchFeedCallCount()
        #expect(calls == 2, "the custom cap should stop paging once persisted count reaches 40")

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished)
        // The targets query is limited to the cap: 40 of the 60 persisted posts.
        #expect(terminal.totalPosts == 40, "targets capped at the custom maxPosts")
        #expect(terminal.itemsCompleted == 40)
    }

    /// A nil cursor ends the page loop even when the cap hasn't been reached;
    /// the loop must not spin forever calling `fetchFeed`.
    @Test
    func pageLoopStopsAtNilCursor() async throws {
        let lemmy = makeLemmy(pages: [
            .init(postCount: 5, nextCursor: "p2"),
            .init(postCount: 5, nextCursor: nil), // feed exhausted
        ])
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: RecordingImageService(), diagnostics: DiagnosticLogSpy(), pacing: .immediate())

        let progress = await runDownload(service: service, lemmy: lemmy)

        let calls = await lemmy.recordedFetchFeedCallCount()
        #expect(calls == 2, "should stop paging at the nil cursor")

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished)
        #expect(terminal.totalPosts == 10)
    }

    /// After paging, every persisted target post must have its comments fetched
    /// exactly once, and its thumbnail + full image warmed through the image
    /// service.
    @Test
    func fetchesCommentsAndImagesPerPost() async throws {
        let lemmy = makeLemmy(pages: [
            .init(postCount: 3, nextCursor: nil),
        ])
        let imageService = RecordingImageService()
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: imageService, diagnostics: DiagnosticLogSpy(), pacing: .immediate())

        let progress = await runDownload(service: service, lemmy: lemmy)

        // Comments: one request per post (server post ids 1, 2, 3).
        let commentIds = await lemmy.recordedFetchCommentsPostIds()
        #expect(Set(commentIds) == Set([1, 2, 3]))
        #expect(commentIds.count == 3, "comments fetched exactly once per post")

        // Images: each post seeds an image url + a thumbnail url -> 2 fetches each.
        let urls = Set(imageService.fetchedURLs.map(\.absoluteString))
        #expect(urls.contains("https://example.com/image.jpg"))
        #expect(urls.contains("https://example.com/thumb/1.jpg"))
        #expect(urls.contains("https://example.com/thumb/2.jpg"))
        #expect(urls.contains("https://example.com/thumb/3.jpg"))
        #expect(imageService.fetchedURLs.count == 6, "thumbnail + full image per post")

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished)
    }

    /// A text post (no image url) must still fetch comments + thumbnail but skip
    /// the full-image fetch (only image posts get their `url` warmed).
    @Test
    func textPostSkipsFullImageFetch() async {
        let lemmy = makeLemmy(
            pages: [.init(postCount: 2, nextCursor: nil)],
            imageUrlForSeededPosts: nil // text posts: url is NULL
        )
        let imageService = RecordingImageService()
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: imageService, diagnostics: DiagnosticLogSpy(), pacing: .immediate())

        _ = await runDownload(service: service, lemmy: lemmy)

        // Only the two thumbnails are warmed; no full-image url exists.
        let urls = imageService.fetchedURLs.map(\.absoluteString)
        #expect(urls.count == 2, "only thumbnails for text posts")
        #expect(urls.allSatisfy { $0.contains("/thumb/") })
    }

    /// Progress must report sane phases/counts: a fetching phase, a content
    /// phase whose `itemsCompleted` climbs to `totalPosts`, and a terminal
    /// `.finished`.
    @Test
    func emitsSaneProgress() async throws {
        let lemmy = makeLemmy(pages: [
            .init(postCount: 4, nextCursor: nil),
        ])
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: RecordingImageService(), diagnostics: DiagnosticLogSpy(), pacing: .immediate())

        let progress = await runDownload(service: service, lemmy: lemmy)

        #expect(progress.contains { $0.phase == .fetchingPosts })
        #expect(progress.contains { $0.phase == .downloadingContent })

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished)
        #expect(terminal.totalPosts == 4)
        #expect(terminal.itemsCompleted == 4, "every target post should be completed")
        #expect(terminal.fractionCompleted == 1)

        // itemsCompleted is monotonic and never exceeds totalPosts.
        let contentCounts = progress
            .filter { $0.phase == .downloadingContent }
            .map(\.itemsCompleted)
        #expect(contentCounts == contentCounts.sorted())
        #expect(contentCounts.allSatisfy { $0 <= 4 })
    }

    /// A single post's `fetchComments` failure must NOT abort the run: the rest
    /// of the posts still complete, every post counts as completed, and the
    /// terminal phase is still `.finished`.
    @Test
    func perPostCommentFailureDoesNotAbort() async throws {
        let lemmy = makeLemmy(
            pages: [.init(postCount: 3, nextCursor: nil)],
            failingCommentPostIds: [2] // post 2's comment fetch throws
        )
        let imageService = RecordingImageService()
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: imageService, diagnostics: DiagnosticLogSpy(), pacing: .immediate())

        let progress = await runDownload(service: service, lemmy: lemmy)

        // All three posts were still attempted (the failure was swallowed).
        let commentIds = await lemmy.recordedFetchCommentsPostIds()
        #expect(Set(commentIds) == Set([1, 2, 3]))

        // The failing post's images are still warmed (best-effort continues).
        #expect(imageService.fetchedURLs.count == 6)

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished)
        #expect(terminal.itemsCompleted == 3, "the failing post still counts as completed")
    }

    /// `fetchComments` no longer THROWS when a walk stops short (page budget
    /// exhausted, or a later page failed) -- it returns `.partial` instead. A
    /// partial completion must not be silently reported as a clean success:
    /// the offline copy would be incomplete. `.pageBudgetExhausted` is a
    /// DETERMINISTIC shortfall -- `LemmyService.maxCommentPages` is a fixed
    /// bound, so re-walking the same thread exhausts it again every time --
    /// so `OutboxFailureClass.classify` marks it permanent and `withRetry`
    /// must not retry it: a single attempt, counted as a genuine failure
    /// (`download.itemFailed`).
    @Test
    func budgetExhaustedCommentCompletionFailsWithoutRetry() async throws {
        let lemmy = makeLemmy(
            pages: [.init(postCount: 1, nextCursor: nil)],
            partialCommentPostIds: [1], // post 1's comment fetch always reports partial
            partialCommentReason: .pageBudgetExhausted
        )
        let imageService = RecordingImageService()
        let diagnostics = DiagnosticLogSpy()
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: imageService, diagnostics: diagnostics, pacing: .immediate())

        let progress = await runDownload(service: service, lemmy: lemmy)

        // A page-budget shortfall must NOT be retried -- exactly one call, not
        // maxRetryAttempts (retrying a fixed, already-exhausted budget can
        // never succeed, so doing so would only waste up to
        // `maxRetryAttempts` paced walks of up to `maxCommentPages` requests
        // each on a foregone conclusion).
        let commentIds = await lemmy.recordedFetchCommentsPostIds()
        #expect(commentIds.count == 1)

        // The failing post still counts as "completed" for progress purposes
        // (best-effort — matches the thrown-error case above) but is recorded
        // as a genuine item failure, not swallowed as clean.
        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished)
        #expect(terminal.itemsCompleted == 1)
        let itemFailedEvents = diagnostics.events(matching: "download.itemFailed")
        #expect(itemFailedEvents.count == 1)
        #expect(itemFailedEvents.first?.metadata?["serverPostId"] == "1")
    }

    /// Unlike a budget shortfall (above), a later page that genuinely FAILED
    /// to fetch (`.pageFetchFailed`) can succeed on a later attempt, so it
    /// stays retryable like any other transient failure: one call per
    /// attempt, up to `maxRetryAttempts`, then counted as a genuine failure.
    @Test
    func pageFetchFailedCommentCompletionIsRetriedThenCountsAsFailure() async throws {
        let lemmy = makeLemmy(
            pages: [.init(postCount: 1, nextCursor: nil)],
            partialCommentPostIds: [1], // post 1's comment fetch always reports partial
            partialCommentReason: .pageFetchFailed
        )
        let imageService = RecordingImageService()
        let diagnostics = DiagnosticLogSpy()
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: imageService, diagnostics: diagnostics, pacing: .immediate())

        let progress = await runDownload(service: service, lemmy: lemmy)

        // A persistently partial completion must be retried like any other
        // transient failure -- one call per attempt, up to maxRetryAttempts.
        let commentIds = await lemmy.recordedFetchCommentsPostIds()
        #expect(commentIds.count == DownloadPacingConfig.immediate().maxRetryAttempts)

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished)
        #expect(terminal.itemsCompleted == 1)
        let itemFailedEvents = diagnostics.events(matching: "download.itemFailed")
        #expect(itemFailedEvents.count == 1)
        #expect(itemFailedEvents.first?.metadata?["serverPostId"] == "1")
    }

    /// `OfflineDownloadService` must thread its `RequestPacer` through to
    /// `fetchComments`'s `pageDelay` hook, not just pace the call's own first
    /// request -- otherwise a multi-page (v4, PieFed) comment walk fires every
    /// page after the first with no pacing at all, defeating the point of the
    /// pacer. This fake doesn't simulate real pagination, so it only confirms
    /// the hook was PROVIDED (non-nil), not that it was invoked N times.
    @Test
    func fetchCommentsIsCalledWithAPageDelayHook() async {
        let lemmy = makeLemmy(pages: [.init(postCount: 1, nextCursor: nil)])
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: RecordingImageService(), diagnostics: DiagnosticLogSpy(), pacing: .immediate())

        _ = await runDownload(service: service, lemmy: lemmy)

        let providedPostIds = await lemmy.recordedFetchCommentsPageDelayProvidedPostIds()
        #expect(providedPostIds == [1])
    }

    /// Cancelling the download from the outside (via `cancelCurrentDownload()`)
    /// must stop further work *and* surface a `.cancelled` terminal to a consumer
    /// that drains the stream to completion.
    ///
    /// This deliberately does NOT cancel the consuming `for await` loop: a
    /// cancelled consumer's `next()` returns nil and would drop the terminal
    /// (the bug the previous version of this test masked, by breaking out of the
    /// loop before the terminal was emitted). Instead the consumer runs
    /// uncancelled and we cancel the *service's internal work task* directly. The
    /// work task observes cancellation, emits `.cancelled`, and finishes — and
    /// because the consumer keeps draining, it observes that terminal.
    @Test
    func cancellationStopsAndEndsCancelled() async throws {
        // Many pages so the page-fetch phase is long enough to be cancelled
        // mid-flight.
        let pages = (0..<50).map { i in
            RecordingLemmyService.Page(postCount: 1, nextCursor: "p\(i + 2)")
        }
        let lemmy = makeLemmy(pages: pages)
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: RecordingImageService(), diagnostics: DiagnosticLogSpy(), pacing: .immediate())

        // A high cap so neither the count-stop nor the page backstop ends the
        // run on its own before the cancel lands: with 1-post pages and an
        // always-non-nil cursor, only cancellation can stop the loop here.
        // (`maxPages(forMaxPosts: 1000)` comfortably exceeds the 50 planned
        // pages, so the loop stays alive long enough to be cancelled.)
        let maxPosts = 1000

        // A continuation the consumer signals once it has seen the first
        // `.fetchingPosts`, so cancellation is driven deterministically (no
        // sleeps) only after the run is actually working.
        let started = AsyncStream<Void>.makeStream()

        // Consume uncancelled to completion, collecting every value. Because we
        // never cancel this task, the `.cancelled` terminal is delivered.
        let consumer = Task { () -> [OfflineDownloadProgress] in
            var collected: [OfflineDownloadProgress] = []
            for await progress in service.download(
                feed: feed,
                lemmyService: lemmy,
                accountId: accountId,
                siteId: siteId,
                commentSort: commentSort,
                showNsfw: false,
                maxPosts: maxPosts
            ) {
                collected.append(progress)
                if progress.phase == .fetchingPosts {
                    started.continuation.yield(())
                }
            }
            return collected
        }

        // Wait until the run has started working, then cancel it from the
        // outside (without tearing down the consumer's stream).
        var startIterator = started.stream.makeAsyncIterator()
        _ = await startIterator.next()
        await service.cancelCurrentDownload()

        let collected = await consumer.value
        let terminal = try #require(collected.last)
        #expect(terminal.phase == .cancelled, "a cancelled run must end on a .cancelled terminal")

        // And the work actually stopped early rather than draining all 50 pages.
        let calls = await lemmy.recordedFetchFeedCallCount()
        #expect(calls < pages.count, "cancellation should stop the page loop before draining all pages")
    }

    /// A pathological server that keeps returning a non-nil cursor while no
    /// longer contributing new posts (all duplicates / an already-populated
    /// feed) must NOT spin the page loop forever: after
    /// `maxConsecutiveEmptyPages` consecutive no-growth pages the loop stops,
    /// so the run terminates `.finished` with the posts gathered so far.
    @Test
    func pageLoopStopsWhenCountPlateaus() async throws {
        // 40 posts arrive on the first page, then the server keeps handing back
        // a cursor forever while inserting nothing.
        let lemmy = makeLemmy(
            pages: [.init(postCount: 40, nextCursor: "p2")],
            exhaustedCursor: "forever" // non-nil cursor on every subsequent call
        )
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: RecordingImageService(), diagnostics: DiagnosticLogSpy(), pacing: .immediate())

        let progress = await runDownload(service: service, lemmy: lemmy)

        // The loop must terminate. The first page seeds 40, then a run of empty
        // pages: the loop tolerates `maxConsecutiveEmptyPages` consecutive
        // no-growth pages before breaking. So 1 (growing) + N (empty, the last
        // of which trips the cap) = 1 + maxConsecutiveEmptyPages calls, bounded
        // well under the maxPages backstop.
        let calls = await lemmy.recordedFetchFeedCallCount()
        #expect(
            calls == 1 + OfflineDownloadService.maxConsecutiveEmptyPages,
            "loop should stop after maxConsecutiveEmptyPages consecutive no-growth pages"
        )
        #expect(
            calls <= OfflineDownloadService.maxPages(forMaxPosts: OfflineDownloadService.defaultMaxPosts),
            "loop must stay within the page backstop"
        )

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished)
        #expect(terminal.totalPosts == 40)
    }

    /// REGRESSION: a feed whose first page was ALREADY loaded by prior browsing
    /// must NOT stop the download after that single no-growth page. The first
    /// `fetchFeed(pageCursor: nil)` re-serves the top page (all duplicates,
    /// de-duped by `appendFeedPage` so the persisted count doesn't grow); the
    /// old single-page "count-didn't-grow" break fired immediately and the
    /// download stopped at the ~handful of already-browsed posts. With the
    /// consecutive-no-growth fix the loop keeps paging and reaches the cap.
    @Test
    func pagePreloadedByBrowsingDoesNotStopDownloadEarly() async throws {
        // Simulate prior browsing: 10 posts (ids 1...10) already in the feed.
        let browsed = try await preSeedBrowsedPosts(count: 10)

        // First download page re-serves the already-browsed posts (zero new),
        // then fresh pages of 30 follow. Fresh ids continue past the 10 browsed.
        let lemmy = makeLemmy(
            pages: [
                .init(postCount: 0, nextCursor: "p2", duplicatePostIds: browsed),
                .init(postCount: 30, nextCursor: "p3"),
                .init(postCount: 30, nextCursor: "p4"),
                .init(postCount: 30, nextCursor: "p5"),
                .init(postCount: 30, nextCursor: nil),
            ],
            firstServerPostId: 11,
            // The pre-seeded "browsed" page occupies feed position 0; continue
            // past it so fetchFeed's pages don't collide on (feedId, position).
            firstPagePosition: 1
        )
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: RecordingImageService(), diagnostics: DiagnosticLogSpy(), pacing: .immediate())

        let progress = await runDownload(service: service, lemmy: lemmy, maxPosts: 100)

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished)
        // 10 browsed + 30*4 fresh = 130 persisted, capped at maxPosts (100).
        // The bug stopped at ~10; the fix must reach the full 100-post cap.
        #expect(
            terminal.totalPosts == 100,
            "an already-browsed first page must not stop the download early"
        )
    }

    /// A single mid-run duplicate page (Hot/Active ranking churn re-serving a
    /// page already in the feed) must NOT stop the download: one no-growth page
    /// is below `maxConsecutiveEmptyPages`, so paging continues and the feed's
    /// genuine end (nil cursor) terminates it.
    @Test
    func singleMidRunDuplicatePageDoesNotStopDownload() async throws {
        // Page 1 seeds 30, page 2 re-serves page 1's posts (churn, zero growth),
        // page 3 seeds 30 more, then the feed ends.
        let firstPageIds = Array(Int64(1)...Int64(30))
        let lemmy = makeLemmy(pages: [
            .init(postCount: 30, nextCursor: "p2"),
            .init(postCount: 0, nextCursor: "p3", duplicatePostIds: firstPageIds),
            .init(postCount: 30, nextCursor: nil),
        ])
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: RecordingImageService(), diagnostics: DiagnosticLogSpy(), pacing: .immediate())

        let progress = await runDownload(service: service, lemmy: lemmy, maxPosts: 100)

        // All three pages are fetched; the churn page in the middle doesn't end
        // the run.
        let calls = await lemmy.recordedFetchFeedCallCount()
        #expect(calls == 3, "a single churn page must not stop the download")

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished)
        #expect(terminal.totalPosts == 60, "30 + 30 unique posts (churn page added none)")
    }

    /// A second concurrent `download` while one is in flight is rejected with a
    /// single `.failed` value (the in-flight guard), without disturbing the
    /// first.
    @Test
    func inFlightGuardRejectsConcurrentDownload() async {
        let pages = (0..<60).map { i in
            RecordingLemmyService.Page(postCount: 1, nextCursor: "p\(i + 2)")
        }
        let lemmy = makeLemmy(pages: pages)
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: RecordingImageService(), diagnostics: DiagnosticLogSpy(), pacing: .immediate())

        // Start the first download and let it begin working.
        let first = Task {
            await runDownload(service: service, lemmy: lemmy)
        }
        // Wait deterministically until the first download has actually claimed
        // the in-flight slot by issuing its first fetchFeed call — no bounded
        // busy-wait, which can flake under CI load. (Mirrors how
        // `cancellationStopsAndEndsCancelled` drives cancellation off a definite
        // signal.)
        await lemmy.firstFetchFeedStarted()

        // A second download against a fresh lemmy must be rejected immediately.
        let secondLemmy = makeLemmy(pages: [.init(postCount: 1, nextCursor: nil)])
        var secondProgress: [OfflineDownloadProgress] = []
        for await p in service.download(
            feed: feed,
            lemmyService: secondLemmy,
            accountId: accountId,
            siteId: siteId,
            commentSort: commentSort,
            showNsfw: false
        ) {
            secondProgress.append(p)
        }

        #expect(secondProgress.count == 1)
        #expect(secondProgress.first?.phase == .failed)
        let secondCalls = await secondLemmy.recordedFetchFeedCallCount()
        #expect(secondCalls == 0, "rejected download must not touch the network")

        _ = await first.value
    }

    // MARK: - Web archive (link capture)

    /// Build a store backed by a temp directory so captured archive files don't
    /// touch the App Group container.
    private func makeArchiveStore() throws -> OfflineWebArchiveStore {
        let baseDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("OfflineDownloadServiceTests-\(UUID().uuidString)", isDirectory: true)
        return try OfflineWebArchiveStore(appDatabase: appDatabase, baseDirectory: baseDirectory)
    }

    /// `offlineDownloadTargetsSync` must surface `externalLinkUrl` for an
    /// external-link post and leave it nil for image / text posts.
    @Test
    func targetsSurfaceExternalLinkUrlForLinkPosts() async throws {
        // An external link (no image/video extension) -> externalLink target.
        let linkLemmy = makeLemmy(
            pages: [.init(postCount: 2, nextCursor: nil)],
            imageUrlForSeededPosts: "https://example.com/article"
        )
        // Seed the posts via a fetchFeed call (the fake writes them to the DB).
        _ = try await linkLemmy.fetchFeed(feed, pageCursor: nil, showNsfw: false)

        let linkTargets = appDatabase.offlineDownloadTargetsSync(feedKey: feed.feedKey, limit: 100)
        #expect(linkTargets.count == 2)
        for target in linkTargets {
            #expect(target.externalLinkUrl?.absoluteString == "https://example.com/article")
            #expect(target.imageUrl == nil, "an external-link post is not an image target")
        }
    }

    /// `offlineDownloadTargetsSync` must leave `externalLinkUrl` nil for image
    /// and text posts (so only link posts get web-archived).
    @Test
    func targetsLeaveExternalLinkNilForImageAndTextPosts() async throws {
        let imageLemmy = makeLemmy(
            pages: [.init(postCount: 1, nextCursor: nil)],
            imageUrlForSeededPosts: "https://example.com/image.jpg"
        )
        _ = try await imageLemmy.fetchFeed(feed, pageCursor: nil, showNsfw: false)
        let imageTargets = appDatabase.offlineDownloadTargetsSync(feedKey: feed.feedKey, limit: 100)
        #expect(imageTargets.first?.externalLinkUrl == nil, "image post has no external-link target")
        #expect(imageTargets.first?.imageUrl != nil, "image post warms its full image")
    }

    /// With `archiveLinks: true`, every external-link target is captured AND
    /// stored; the recorded URLs match the seeded links and the store holds them.
    @Test
    func archiveLinksTrueCapturesAndStoresLinkPosts() async throws {
        let lemmy = makeLemmy(
            pages: [.init(postCount: 3, nextCursor: nil)],
            imageUrlForSeededPosts: "https://example.com/article"
        )
        let capturer = RecordingWebArchiveCapturer()
        let store = try makeArchiveStore()
        let service = OfflineDownloadService(
            appDatabase: appDatabase,
            imageService: RecordingImageService(),
            diagnostics: DiagnosticLogSpy(),
            pacing: .immediate(),
            webArchiveCapturer: capturer,
            webArchiveStore: store
        )

        var collected: [OfflineDownloadProgress] = []
        for await progress in service.download(
            feed: feed,
            lemmyService: lemmy,
            accountId: accountId,
            siteId: siteId,
            commentSort: commentSort,
            showNsfw: false,
            maxPosts: OfflineDownloadService.defaultMaxPosts,
            archiveLinks: true
        ) {
            collected.append(progress)
        }

        // Every external-link post was captured.
        let captured = Set(capturer.capturedURLs.map(\.absoluteString))
        #expect(captured == ["https://example.com/article"])
        #expect(capturer.capturedURLs.count == 3, "one capture per external-link post")

        // And each was stored (a single distinct URL across 3 posts -> the
        // store upserts the same row, so the archive is present).
        let link = try #require(URL(string: "https://example.com/article"))
        #expect(store.hasWebArchiveSync(forURL: link))

        let terminal = try #require(collected.last)
        #expect(terminal.phase == .finished)
        // Web archive is part of per-post work, so itemsCompleted still == posts
        // (no double count).
        #expect(terminal.itemsCompleted == 3)
        #expect(terminal.totalPosts == 3)
    }

    /// With `archiveLinks: false` (the default), no link is captured even though
    /// the posts are external links.
    @Test
    func archiveLinksFalseCapturesNothing() async throws {
        let lemmy = makeLemmy(
            pages: [.init(postCount: 2, nextCursor: nil)],
            imageUrlForSeededPosts: "https://example.com/article"
        )
        let capturer = RecordingWebArchiveCapturer()
        let store = try makeArchiveStore()
        let service = OfflineDownloadService(
            appDatabase: appDatabase,
            imageService: RecordingImageService(),
            diagnostics: DiagnosticLogSpy(),
            pacing: .immediate(),
            webArchiveCapturer: capturer,
            webArchiveStore: store
        )

        let progress = await runDownload(service: service, lemmy: lemmy)

        #expect(capturer.capturedURLs.isEmpty, "archiveLinks: false must not capture any page")
        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished)
    }

    /// A capturer that returns nil (load error / timeout) must NOT abort the run:
    /// the capture is attempted for each link, nothing is stored, and the run
    /// still finishes with every post completed.
    @Test
    func nilCaptureDoesNotAbortRun() async throws {
        let lemmy = makeLemmy(
            pages: [.init(postCount: 3, nextCursor: nil)],
            imageUrlForSeededPosts: "https://example.com/article"
        )
        let capturer = RecordingWebArchiveCapturer(returnsNil: true)
        let store = try makeArchiveStore()
        let service = OfflineDownloadService(
            appDatabase: appDatabase,
            imageService: RecordingImageService(),
            diagnostics: DiagnosticLogSpy(),
            pacing: .immediate(),
            webArchiveCapturer: capturer,
            webArchiveStore: store
        )

        var collected: [OfflineDownloadProgress] = []
        for await progress in service.download(
            feed: feed,
            lemmyService: lemmy,
            accountId: accountId,
            siteId: siteId,
            commentSort: commentSort,
            showNsfw: false,
            maxPosts: OfflineDownloadService.defaultMaxPosts,
            archiveLinks: true
        ) {
            collected.append(progress)
        }

        // Capture was attempted for each link (best-effort) but nothing stored.
        #expect(capturer.capturedURLs.count == 3)
        let link = try #require(URL(string: "https://example.com/article"))
        #expect(store.hasWebArchiveSync(forURL: link) == false, "a nil capture stores nothing")

        let terminal = try #require(collected.last)
        #expect(terminal.phase == .finished, "a failed capture must not abort the run")
        #expect(terminal.itemsCompleted == 3, "every post still counts as completed")
    }

    /// REGRESSION: the archive must be STORED under the same (sanitized) URL the
    /// open path LOOKS IT UP by. The download keys captures on
    /// `sanitizeURL(externalLinkUrl)`; the open path (`AppService`) sanitizes the
    /// tapped link with the identical transform before lookup. If the two keys
    /// diverged, the archive would be saved but never found ("not saved for
    /// offline" despite a successful download).
    ///
    /// Here the sanitizer rewrites `?utm_source=x` away (modelling
    /// `URLSanitizer`'s tracking-param strip). After the download: a lookup by the
    /// SANITIZED url (`…/article`) must succeed, and a lookup by the RAW url
    /// (`…/article?utm_source=x`) must FAIL — which is exactly the round-trip the
    /// bug would have failed.
    @Test
    func archiveIsKeyedOnSanitizedURL() async throws {
        let rawLink = "https://example.com/article?utm_source=x"
        let sanitizedLink = "https://example.com/article"

        let lemmy = makeLemmy(
            pages: [.init(postCount: 1, nextCursor: nil)],
            imageUrlForSeededPosts: rawLink
        )
        let capturer = RecordingWebArchiveCapturer()
        let store = try makeArchiveStore()
        let service = OfflineDownloadService(
            appDatabase: appDatabase,
            imageService: RecordingImageService(),
            diagnostics: DiagnosticLogSpy(),
            pacing: .immediate(),
            webArchiveCapturer: capturer,
            webArchiveStore: store
        )

        // A sanitizer that strips the query (the part `URLSanitizer` would remove).
        let sanitize: @Sendable (URL) -> URL = { url in
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.query = nil
            return components?.url ?? url
        }

        var collected: [OfflineDownloadProgress] = []
        for await progress in service.download(
            feed: feed,
            lemmyService: lemmy,
            accountId: accountId,
            siteId: siteId,
            commentSort: commentSort,
            showNsfw: false,
            maxPosts: OfflineDownloadService.defaultMaxPosts,
            archiveLinks: true,
            sanitizeURL: sanitize
        ) {
            collected.append(progress)
        }

        let terminal = try #require(collected.last)
        #expect(terminal.phase == .finished)

        // The capturer was driven with the SANITIZED url, not the raw one.
        #expect(capturer.capturedURLs.map(\.absoluteString) == [sanitizedLink])

        // Lookup by the sanitized url (what the open path computes) succeeds...
        let sanitizedURL = try #require(URL(string: sanitizedLink))
        #expect(store.hasWebArchiveSync(forURL: sanitizedURL), "archive must be found by the sanitized key")

        // ...and a lookup by the raw url does NOT (the store never keyed on it).
        let rawURL = try #require(URL(string: rawLink))
        #expect(
            store.hasWebArchiveSync(forURL: rawURL) == false,
            "the raw (unsanitized) url must NOT find the archive — that mismatch was the bug"
        )
    }

    // MARK: - Paced + retried content fetch

    /// A comment fetch that fails is now retried before being swallowed: with a
    /// permanently-failing comment id, the fake sees `maxRetryAttempts` calls for
    /// that post (not one), and the run still finishes (best-effort per item).
    @Test
    func commentFetchIsRetriedThenSwallowed() async throws {
        let lemmy = makeLemmy(
            pages: [.init(postCount: 1, nextCursor: nil)],
            failingCommentPostIds: [1]
        )
        let service = OfflineDownloadService(
            appDatabase: appDatabase, imageService: RecordingImageService(),
            diagnostics: DiagnosticLogSpy(), pacing: .immediate()
        )

        let progress = await runDownload(service: service, lemmy: lemmy)

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished, "a failing comment must not fail the run")
        #expect(terminal.itemsCompleted == 1, "the post still counts as completed (best-effort)")

        // Post id 1 was retried: attempts == maxRetryAttempts, all recorded.
        let commentCalls = await lemmy.recordedFetchCommentsPostIds().filter { $0 == 1 }
        #expect(commentCalls.count == DownloadPacingConfig.immediate().maxRetryAttempts)
    }

    /// When the image service never yields `.ready` (stream closes without a
    /// value, which `drainImageFetch` maps to `OfflineImageFetchError.notReady`),
    /// `warmImage` retries up to `maxImageRetryAttempts` times and then swallows
    /// the error (best-effort). The post still counts as completed and the run
    /// finishes; the image service records one call per attempt.
    @Test
    func imageWarmingRetriesThenSwallowsOnPersistentFailure() async throws {
        let lemmy = makeLemmy(pages: [.init(postCount: 1, nextCursor: nil)])
        let imageService = RecordingImageService(yieldsReady: false)
        let service = OfflineDownloadService(
            appDatabase: appDatabase, imageService: imageService,
            diagnostics: DiagnosticLogSpy(), pacing: .immediate()
        )

        let progress = await runDownload(service: service, lemmy: lemmy)

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished, "a failed image warm must not abort the run")
        #expect(terminal.itemsCompleted == 1, "the post still counts as completed (best-effort)")

        // The thumbnail for server post id 1 is the only image warm target
        // (post has no image url via the default seed with imageUrlForSeededPosts
        // still set — but RecordingImageService.fetch(_:downsampleTo:) is what
        // warmImage calls for both full and thumbnail; here the full-image url is
        // also set, so both are attempted). Each warm retries maxImageRetryAttempts
        // times before giving up, so total recorded fetches = 2 * maxImageRetryAttempts
        // (thumbnail + full image, each attempted that many times).
        let pacing = DownloadPacingConfig.immediate()
        // Each of the 2 image urls is attempted maxImageRetryAttempts times.
        let expectedFetches = 2 * pacing.maxImageRetryAttempts
        #expect(
            imageService.fetchedURLs.count == expectedFetches,
            "each image warm retries exactly maxImageRetryAttempts times"
        )
        // The thumbnail url for server post id 1 must be among the recorded fetches.
        let thumbnailURL = "https://example.com/thumb/1.jpg"
        let thumbnailCount = imageService.fetchedURLs.filter { $0.absoluteString == thumbnailURL }.count
        #expect(thumbnailCount == pacing.maxImageRetryAttempts, "thumbnail retried maxImageRetryAttempts times")
    }

    // MARK: - Paced + retried page fetch

    /// A page that fails with a transient error (HTTP 503) must be retried
    /// transparently. The finished run must carry no warning and the full post
    /// count.
    @Test
    func transientPageFailureIsRetried() async throws {
        let lemmy = makeLemmy(pages: [
            .init(postCount: 5, nextCursor: "p2"),
            .init(postCount: 5, nextCursor: nil, transientFailures: 2),
        ])
        let diagnostics = DiagnosticLogSpy()
        let service = OfflineDownloadService(
            appDatabase: appDatabase, imageService: RecordingImageService(),
            diagnostics: diagnostics, pacing: .immediate()
        )
        let progress = await runDownload(service: service, lemmy: lemmy)
        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished, "a retried transient failure must not fail the run")
        #expect(terminal.warningMessage == nil, "a fully-recovered run has no partial notice")
        #expect(terminal.totalPosts == 10)
        #expect(!diagnostics.events(matching: "download.retry").isEmpty)
    }

    /// A page that permanently fails (HTTP 403) after at least one page has
    /// already landed must NOT abort the run. The run finishes as partial
    /// (carrying a warning) with only the posts that were already persisted.
    @Test
    func permanentPageFailureAfterFirstPageFinishesPartial() async throws {
        let lemmy = makeLemmy(pages: [
            .init(postCount: 5, nextCursor: "p2"),
            .init(postCount: 0, nextCursor: nil, permanentFailure: true),
        ])
        let diagnostics = DiagnosticLogSpy()
        let service = OfflineDownloadService(
            appDatabase: appDatabase, imageService: RecordingImageService(),
            diagnostics: diagnostics, pacing: .immediate()
        )
        let progress = await runDownload(service: service, lemmy: lemmy)
        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished, "partial success is a finished run, not a failure")
        #expect(terminal.warningMessage != nil, "a partial run carries a warning notice")
        #expect(terminal.totalPosts == 5, "content phase runs over the 5 kept posts")
        #expect(terminal.itemsCompleted == 5)
        #expect(!diagnostics.events(matching: "download.pageFetchIncomplete").isEmpty)
    }

    /// A permanent failure on the very first page (zero posts persisted) must
    /// produce a `.failed` terminal state, not a partial finish.
    @Test
    func permanentFirstPageFailureFailsRun() async throws {
        let lemmy = makeLemmy(pages: [
            .init(postCount: 0, nextCursor: nil, permanentFailure: true),
        ])
        let service = OfflineDownloadService(
            appDatabase: appDatabase, imageService: RecordingImageService(),
            diagnostics: DiagnosticLogSpy(), pacing: .immediate()
        )
        let progress = await runDownload(service: service, lemmy: lemmy)
        let terminal = try #require(progress.last)
        #expect(terminal.phase == .failed)
        #expect(terminal.failureMessage != nil)
    }

    // MARK: - Aggregated per-item failure diagnostics

    /// A run whose images never reach `.ready` (they fail for good) must surface
    /// the failure as an aggregate `imageWarmFailures` count in the
    /// `download.finish` summary — NOT as one durable event per image (that
    /// per-item chatter is OSLog-only).
    @Test
    func imageWarmFailuresAppearInFinishSummary() async throws {
        let lemmy = makeLemmy(pages: [.init(postCount: 1, nextCursor: nil)])
        // Every warm's stream closes without `.ready`, so both the thumbnail and
        // the full-image warm fail for good after their retries.
        let imageService = RecordingImageService(yieldsReady: false)
        let diagnostics = DiagnosticLogSpy()
        let service = OfflineDownloadService(
            appDatabase: appDatabase, imageService: imageService,
            diagnostics: diagnostics, pacing: .immediate()
        )

        let progress = await runDownload(service: service, lemmy: lemmy)
        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished, "a failed image warm must not abort the run")

        let finish = try #require(diagnostics.events(matching: "download.finish").last)
        let raw = try #require(finish.metadata?["imageWarmFailures"])
        let count = try #require(Int(raw))
        #expect(count >= 1, "a run whose images never reach .ready must report imageWarmFailures in the summary")
    }

    /// A transient COMMENT failure in the content phase must now be visible: each
    /// retry records a `download.retry` event tagged `phase == "content"` (the
    /// page-fetch retries were already visible; this proves the content-phase ones
    /// are too).
    @Test
    func contentPhaseCommentRetryIsRecorded() async throws {
        // Post 1's comment fetch throws every time -> it is retried, and each
        // retry records a content-phase `download.retry`.
        let lemmy = makeLemmy(
            pages: [.init(postCount: 1, nextCursor: nil)],
            failingCommentPostIds: [1]
        )
        let diagnostics = DiagnosticLogSpy()
        let service = OfflineDownloadService(
            appDatabase: appDatabase, imageService: RecordingImageService(),
            diagnostics: diagnostics, pacing: .immediate()
        )

        let progress = await runDownload(service: service, lemmy: lemmy)
        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished, "a failing comment must not fail the run")

        // The single page fetch here has no transient failure, so every
        // `download.retry` is a content-phase (comment) retry.
        let contentRetries = diagnostics.events(matching: "download.retry")
            .filter { $0.metadata?["phase"] == "content" }
        #expect(!contentRetries.isEmpty, "a retried comment fetch must record a content-phase download.retry")
        #expect(
            contentRetries.allSatisfy { $0.metadata?["serverPostId"] == "1" },
            "a content-phase retry names the post it is retrying"
        )
    }

    /// A 503 (server pushback) page failure's `download.retry` must be tagged
    /// `phase == "page"` AND `pushback == "true"`, so the log viewer can tell
    /// rate-limiting apart from a plain transient blip.
    @Test
    func pageRetryTagsPushbackAndPhase() async throws {
        let lemmy = makeLemmy(pages: [
            .init(postCount: 5, nextCursor: "p2"),
            // The second page fails once with HTTP 503 (server pushback), then
            // recovers.
            .init(postCount: 5, nextCursor: nil, transientFailures: 1),
        ])
        let diagnostics = DiagnosticLogSpy()
        let service = OfflineDownloadService(
            appDatabase: appDatabase, imageService: RecordingImageService(),
            diagnostics: diagnostics, pacing: .immediate()
        )

        let progress = await runDownload(service: service, lemmy: lemmy)
        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished, "a retried transient failure must not fail the run")

        let pageRetries = diagnostics.events(matching: "download.retry")
            .filter { $0.metadata?["phase"] == "page" }
        let retry = try #require(pageRetries.first, "a 503 page failure must record a page-phase download.retry")
        #expect(retry.metadata?["pushback"] == "true", "a 503 is server pushback")
    }

    /// An `archiveLinks` run whose capture returns nil (load error / timeout) must
    /// surface the failure as an aggregate `archiveCaptureFailures` count in the
    /// `download.finish` summary (again, no per-item durable event).
    @Test
    func archiveCaptureFailuresAppearInFinishSummary() async throws {
        // External-link posts (no image extension) so the archive branch runs.
        let lemmy = makeLemmy(
            pages: [.init(postCount: 3, nextCursor: nil)],
            imageUrlForSeededPosts: "https://example.com/article"
        )
        let capturer = RecordingWebArchiveCapturer(returnsNil: true)
        let store = try makeArchiveStore()
        let diagnostics = DiagnosticLogSpy()
        let service = OfflineDownloadService(
            appDatabase: appDatabase,
            imageService: RecordingImageService(),
            diagnostics: diagnostics,
            pacing: .immediate(),
            webArchiveCapturer: capturer,
            webArchiveStore: store
        )

        var collected: [OfflineDownloadProgress] = []
        for await progress in service.download(
            feed: feed,
            lemmyService: lemmy,
            accountId: accountId,
            siteId: siteId,
            commentSort: commentSort,
            showNsfw: false,
            maxPosts: OfflineDownloadService.defaultMaxPosts,
            archiveLinks: true
        ) {
            collected.append(progress)
        }
        let terminal = try #require(collected.last)
        #expect(terminal.phase == .finished, "a failed capture must not abort the run")

        let finish = try #require(diagnostics.events(matching: "download.finish").last)
        let raw = try #require(finish.metadata?["archiveCaptureFailures"])
        let count = try #require(Int(raw))
        #expect(count >= 1, "an archiveLinks run whose capture returns nil must report archiveCaptureFailures")
    }
}
