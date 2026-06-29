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
    private let commentSort = Components.Schemas.CommentSortType.Hot

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
        exhaustedCursor: String? = nil
    ) -> RecordingLemmyService {
        RecordingLemmyService(
            appDatabase: appDatabase,
            accountId: accountId,
            communityId: communityId,
            personId: personId,
            pages: pages,
            imageUrlForSeededPosts: imageUrlForSeededPosts,
            failingCommentPostIds: failingCommentPostIds,
            exhaustedCursor: exhaustedCursor
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
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: RecordingImageService())

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
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: imageService)

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
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: RecordingImageService())

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
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: imageService)

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
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: imageService)

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
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: RecordingImageService())

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
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: imageService)

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
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: RecordingImageService())

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
    /// feed) must NOT spin the page loop forever: the count-didn't-grow guard
    /// breaks the loop the first page that adds nothing, so the run terminates
    /// `.finished` with the posts gathered so far.
    @Test
    func pageLoopStopsWhenCountPlateaus() async throws {
        // 40 posts arrive over the first pages, then the server keeps handing
        // back a cursor forever while inserting nothing.
        let lemmy = makeLemmy(
            pages: [.init(postCount: 40, nextCursor: "p2")],
            exhaustedCursor: "forever" // non-nil cursor on every subsequent call
        )
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: RecordingImageService())

        let progress = await runDownload(service: service, lemmy: lemmy)

        // The loop must terminate. After the first page (40 posts) the next
        // page adds nothing -> count-didn't-grow break. So exactly 2 fetchFeed
        // calls, bounded well under the maxPages backstop.
        let calls = await lemmy.recordedFetchFeedCallCount()
        #expect(calls == 2, "loop should break the first page that adds no new posts")
        #expect(
            calls <= OfflineDownloadService.maxPages(forMaxPosts: OfflineDownloadService.defaultMaxPosts),
            "loop must stay within the page backstop"
        )

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished)
        #expect(terminal.totalPosts == 40)
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
        let service = OfflineDownloadService(appDatabase: appDatabase, imageService: RecordingImageService())

        // Start the first download and let it begin working.
        let first = Task {
            await runDownload(service: service, lemmy: lemmy)
        }
        // Wait until the first download has actually claimed the in-flight slot
        // by issuing at least one fetchFeed call.
        var attempts = 0
        while await lemmy.recordedFetchFeedCallCount() == 0, attempts < 1000 {
            await Task.yield()
            attempts += 1
        }

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
}
