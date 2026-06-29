//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreGraphics
import Foundation
import LemmyKit
import OSLog

private let logger = Logger.offlineDownloadService

/// Predownloads a feed for offline browsing.
///
/// The feed, post-detail, and image surfaces are already GRDB / disk-cache
/// first, so they render offline *once the data is present*. This service fills
/// that data: it bulk-fetches feed pages (persisted to GRDB), each post's
/// comment tree (persisted), and each post's images (warmed into the image
/// service's durable disk cache). The UI for triggering and observing a
/// download is a separate slice; this is the data-layer engine.
///
/// One download runs at a time (see the in-flight guard on
/// ``download(feed:lemmyService:accountId:siteId:commentSort:showNsfw:)``).
public actor OfflineDownloadService {
    private let appDatabase: AppDatabase
    private let imageService: any ImageServiceType

    /// Guards against two overlapping downloads. The check-and-set is done
    /// inside the actor (the synchronous `markInFlightIfFree` hop) so two near
    /// simultaneous `download(...)` calls can't both observe "free".
    private var isDownloading = false

    /// The in-flight download's work task, retained so a caller can cancel the
    /// run *without* tearing down its progress stream (see
    /// ``cancelCurrentDownload()``). A consumer that simply stops iterating also
    /// cancels the run, but via the stream's `onTermination` — and a torn-down
    /// stream can no longer deliver the `.cancelled` terminal. Explicit
    /// cancellation lets the consumer keep draining and observe that terminal.
    private var workTask: Task<Void, Never>?

    /// Default post cap when a caller doesn't specify one (see the `maxPosts`
    /// parameter of ``download(feed:lemmyService:accountId:siteId:commentSort:showNsfw:maxPosts:)``).
    /// Bounds both the page-fetch loop and the content phase so a download of a
    /// busy feed stays a finite, polite amount of work.
    public static let defaultMaxPosts = 100

    /// The smallest page size we assume a healthy feed returns, used to scale the
    /// per-run page backstop (``maxPages(forMaxPosts:)``) to the chosen `maxPosts`.
    /// Deliberately conservative (well under Lemmy's typical ~30-50 posts/page) so
    /// the backstop always allows *enough* pages to reach the target on a normal
    /// feed, and only bites a pathological one.
    private static let minExpectedPageSize = 10

    /// Extra pages allowed beyond the count-derived minimum, absorbing a feed that
    /// trickles a few duplicates per page without prematurely capping a legitimate
    /// run.
    private static let maxPagesBuffer = 5

    /// Hard cap on the number of feed pages a single download will request, scaled
    /// to `maxPosts`. A backstop against a pathological server that keeps handing
    /// back a non-nil cursor while trickling little or no new content: even if the
    /// count-didn't-grow guard somehow doesn't fire (e.g. the server adds one new
    /// post per page), this guarantees the page loop terminates.
    ///
    /// Scaled — rather than a fixed 20 — so a larger `maxPosts` (250 / 500) still
    /// gets enough pages to reach its target on a normal feed: at
    /// ``minExpectedPageSize`` posts/page plus ``maxPagesBuffer``, the backstop
    /// comfortably clears the cap for a healthy feed and only bounds a pathological
    /// one. The count-didn't-grow break (in ``fetchPages``) remains the primary
    /// infinite-loop guard; this is the secondary, always-terminating one.
    static func maxPages(forMaxPosts maxPosts: Int) -> Int {
        let pagesToReachTarget = (maxPosts + minExpectedPageSize - 1) / minExpectedPageSize
        return pagesToReachTarget + maxPagesBuffer
    }

    /// Concurrency cap for the per-post content phase. Deliberately small: each
    /// unit hits the instance for a comment tree plus up to two images, so a
    /// higher fan-out would hammer the server (and trip rate limits) for no real
    /// throughput win on a single host.
    public static let contentConcurrency = 4

    /// The downsample target for predownloaded thumbnails. Reuses the shared
    /// `ImageService.feedThumbnailPointSize` so the predownloaded thumbnail is
    /// cached under the exact key the feed cell — and the post-detail header's
    /// thumbnail-seed probe — later reads, giving an instant offline first paint.
    private static let thumbnailDownsampleSize = ImageService.feedThumbnailPointSize

    /// The downsample target for a post's full image. Generous so the cached
    /// bitmap is large enough for the post-detail header and the full-screen
    /// viewer's initial display without a full-resolution decode.
    private static let fullImageDownsampleSize = CGSize(width: 2048, height: 2048)

    public init(appDatabase: AppDatabase, imageService: any ImageServiceType) {
        self.appDatabase = appDatabase
        self.imageService = imageService
    }

    /// Download `feed` for offline browsing and stream progress.
    ///
    /// The returned `AsyncStream` emits ``OfflineDownloadProgress`` snapshots and
    /// finishes with exactly one terminal value (`.finished`, `.failed`, or
    /// `.cancelled`).
    ///
    /// Algorithm:
    /// 1. **fetchingPosts** — page through `lemmyService.fetchFeed` (which
    ///    persists each page to GRDB), accumulating the cursor, until the
    ///    persisted post count reaches `maxPosts`, the cursor is nil (feed
    ///    exhausted), or the task is cancelled.
    /// 2. Read the download targets from the now-persisted feed
    ///    (`offlineDownloadTargetsSync`).
    /// 3. **downloadingContent** — process the targets through a bounded
    ///    `TaskGroup` (cap ``contentConcurrency``): per post, fetch+persist its
    ///    comment tree and warm its thumbnail (and full image, for image posts)
    ///    into the durable disk cache.
    /// 4. Emit `.finished` (or `.cancelled` / `.failed`).
    ///
    /// **Posts before comments:** `fetchComments` is a no-op when the post isn't
    /// already in the database, so the page-fetch phase must fully complete
    /// before the content phase starts.
    ///
    /// **Best-effort per item:** a single post's comment- or image-fetch failure
    /// is swallowed (the post still counts as completed) so one bad post can't
    /// abort the whole download. Only a fatal failure of the *first* feed page
    /// while online ends the run as `.failed`.
    ///
    /// **In-flight guard:** if a download is already running, the returned
    /// stream immediately emits a single `.failed` (with an explanatory message)
    /// and finishes — callers should not start a second download.
    ///
    /// **Cancellation:** the stream's `onTermination` cancels the internal work
    /// task. So a consumer that stops iterating (or whose surrounding task is
    /// cancelled) cancels the download; the run then ends with a `.cancelled`
    /// terminal value.
    ///
    /// - Parameters:
    ///   - feed: The feed to predownload, identified by its stable `feedKey`.
    ///   - lemmyService: The per-account Lemmy service used to fetch pages and
    ///     comment trees. Passed in (rather than stored) so the service stays
    ///     account-agnostic and a download targets whichever account opened it.
    ///   - accountId: The local account row id (reserved for future per-account
    ///     bookkeeping; the feed fetch already scopes to the account behind
    ///     `lemmyService`).
    ///   - siteId: The local site row id (reserved, as above).
    ///   - commentSort: The comment sort order to fetch each post's tree with.
    ///   - showNsfw: Forwarded to `fetchFeed` so NSFW filtering stays
    ///     server-side and consistent with the live feed.
    ///   - maxPosts: The maximum number of posts to fetch + predownload. Bounds
    ///     both the page-fetch loop (which stops once the persisted count reaches
    ///     this) and the content phase (the targets query is limited to this).
    ///     The per-run page backstop (``maxPages(forMaxPosts:)``) scales with it.
    ///     Defaults to ``defaultMaxPosts``.
    public nonisolated func download(
        feed: FeedHandle,
        lemmyService: any LemmyServiceType,
        accountId: Int64,
        siteId: Int64,
        commentSort: Components.Schemas.CommentSortType,
        showNsfw: Bool,
        maxPosts: Int = defaultMaxPosts
    ) -> AsyncStream<OfflineDownloadProgress> {
        AsyncStream { continuation in
            // Wrap the work task in a holder so the task's own body can claim the
            // in-flight slot and register itself atomically (claim + store in one
            // actor hop), avoiding a race where a rejected concurrent download
            // clobbers the live download's retained task.
            let holder = WorkTaskHolder()
            let work = Task {
                let claimed = await self.beginDownload(workTask: holder)
                await self.run(
                    feed: feed,
                    lemmyService: lemmyService,
                    commentSort: commentSort,
                    showNsfw: showNsfw,
                    maxPosts: maxPosts,
                    claimedSlot: claimed,
                    emit: { continuation.yield($0) }
                )
                continuation.finish()
            }
            holder.task = work
            // Stopping the consuming task (or the UI cancelling) terminates the
            // stream, which cancels the work task. `run` honours `Task.isCancelled`
            // between steps and emits a final `.cancelled`. (Note: a torn-down
            // stream can't deliver that terminal — for an observable cancelled
            // state, use `cancelCurrentDownload()` instead of stopping iteration.)
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    /// Cancel the in-flight download, if any, without tearing down its progress
    /// stream. The run honours `Task.isCancelled` between steps and emits a final
    /// `.cancelled`, which a still-draining consumer then observes. No-op when no
    /// download is running.
    ///
    /// Prefer this over stopping the consumer when the UI needs to render the
    /// cancelled state: a consumer that stops iterating cancels the run via the
    /// stream's `onTermination`, but the torn-down stream can no longer deliver
    /// the `.cancelled` terminal.
    public func cancelCurrentDownload() {
        workTask?.cancel()
    }

    // MARK: - Private

    /// One-shot mutable box for handing a `Task` to its own body. The task is
    /// assigned after construction (so the body can reference it), then read
    /// once inside the actor. Only ever touched on the actor, so the
    /// `@unchecked Sendable` is sound.
    private final class WorkTaskHolder: @unchecked Sendable {
        var task: Task<Void, Never>?
    }

    /// Atomically claim the in-flight slot AND retain the work task in one actor
    /// hop. Returns false when a download is already running (the caller then
    /// emits `.failed` and does not retain its task, so a rejected concurrent
    /// download can't clobber the live download's `workTask`).
    private func beginDownload(workTask holder: WorkTaskHolder) -> Bool {
        guard !isDownloading else { return false }
        isDownloading = true
        workTask = holder.task
        return true
    }

    private func clearInFlight() {
        isDownloading = false
        workTask = nil
    }

    private func run(
        feed: FeedHandle,
        lemmyService: any LemmyServiceType,
        commentSort: Components.Schemas.CommentSortType,
        showNsfw: Bool,
        maxPosts: Int,
        claimedSlot: Bool,
        emit: @Sendable (OfflineDownloadProgress) -> Void
    ) async {
        guard claimedSlot else {
            logger.info("Offline download already in flight; rejecting concurrent request")
            emit(OfflineDownloadProgress(
                phase: .failed,
                failureMessage: "A download is already in progress."
            ))
            return
        }
        defer { clearInFlight() }

        // Phase 1: page through the feed, persisting each page to GRDB.
        let postsFetched: Int
        do {
            postsFetched = try await fetchPages(
                feed: feed,
                lemmyService: lemmyService,
                showNsfw: showNsfw,
                maxPosts: maxPosts,
                emit: emit
            )
        } catch is CancellationError {
            // Surface however many posts the cancelled page loop had already
            // persisted so the terminal `.cancelled` (and its
            // `fractionCompleted`) reflects real progress rather than snapping
            // back to zero.
            let persisted = appDatabase.offlineFeedPostCountSync(feedKey: feed.feedKey)
            emit(OfflineDownloadProgress(phase: .cancelled, postsFetched: persisted))
            return
        } catch {
            logger.error("Offline download failed during page fetch: \(String(describing: error), privacy: .public)")
            emit(OfflineDownloadProgress(
                phase: .failed,
                failureMessage: "Could not download the feed."
            ))
            return
        }

        if Task.isCancelled {
            emit(OfflineDownloadProgress(phase: .cancelled, postsFetched: postsFetched))
            return
        }

        // Phase 2: read the download targets from the now-persisted feed,
        // limited to the chosen cap.
        let targets = appDatabase.offlineDownloadTargetsSync(
            feedKey: feed.feedKey,
            limit: maxPosts
        )
        let totalPosts = targets.count

        // Phase 3: download per-post content (comments + images), best-effort.
        let completed = await downloadContent(
            targets: targets,
            lemmyService: lemmyService,
            commentSort: commentSort,
            postsFetched: postsFetched,
            totalPosts: totalPosts,
            emit: emit
        )

        if Task.isCancelled {
            emit(OfflineDownloadProgress(
                phase: .cancelled,
                postsFetched: postsFetched,
                totalPosts: totalPosts,
                itemsCompleted: completed
            ))
            return
        }

        emit(OfflineDownloadProgress(
            phase: .finished,
            postsFetched: postsFetched,
            totalPosts: totalPosts,
            itemsCompleted: completed
        ))
    }

    /// Page through `feed` until the persisted post count reaches `maxPosts`,
    /// the cursor is nil, or the task is cancelled. Returns the final persisted
    /// post count. Rethrows a `fetchFeed` failure (handled as fatal by `run`).
    private func fetchPages(
        feed: FeedHandle,
        lemmyService: any LemmyServiceType,
        showNsfw: Bool,
        maxPosts: Int,
        emit: @Sendable (OfflineDownloadProgress) -> Void
    ) async throws -> Int {
        emit(OfflineDownloadProgress(phase: .fetchingPosts))

        // Scale the page backstop to the chosen post cap so a larger run still
        // gets enough pages to reach its target on a healthy feed.
        let maxPages = Self.maxPages(forMaxPosts: maxPosts)

        var cursor: String? = nil
        var persistedCount = appDatabase.offlineFeedPostCountSync(feedKey: feed.feedKey)
        var pagesFetched = 0

        repeat {
            try Task.checkCancellation()

            // Snapshot the count before this page so we can detect a page that
            // contributed no new posts (all duplicates already in the feed).
            let beforeCount = persistedCount

            let nextCursor = try await lemmyService.fetchFeed(
                feed,
                pageCursor: cursor,
                showNsfw: showNsfw
            )
            pagesFetched += 1

            persistedCount = appDatabase.offlineFeedPostCountSync(feedKey: feed.feedKey)
            emit(OfflineDownloadProgress(phase: .fetchingPosts, postsFetched: persistedCount))

            // Count-didn't-grow break: the page upserted only posts already in
            // the feed (a feed with fewer than maxPosts unique posts, or a
            // re-download of an already-populated feed). The cursor may stay
            // non-nil forever in that case, so treat "no new posts" as the end
            // of useful content and stop — otherwise the loop never terminates.
            guard persistedCount > beforeCount else { break }

            // nil cursor means the server has no more pages.
            guard let nextCursor, !nextCursor.isEmpty else { break }
            cursor = nextCursor

            // Hard page-count backstop: even a server that trickles one new
            // post per page (so the count keeps creeping up and the
            // count-didn't-grow guard never fires) can't keep the loop alive
            // indefinitely.
            guard pagesFetched < maxPages else { break }
        } while persistedCount < maxPosts

        return persistedCount
    }

    /// Process `targets` through a bounded `TaskGroup` (cap
    /// ``contentConcurrency``). Per post: fetch+persist its comment tree and
    /// warm its thumbnail (and full image, when present) into the durable disk
    /// cache. A per-post failure is swallowed; the post still counts as
    /// completed. Returns the number of posts processed. Emits a progress
    /// snapshot after each completed post.
    private func downloadContent(
        targets: [OfflineDownloadTarget],
        lemmyService: any LemmyServiceType,
        commentSort: Components.Schemas.CommentSortType,
        postsFetched: Int,
        totalPosts: Int,
        emit: @Sendable (OfflineDownloadProgress) -> Void
    ) async -> Int {
        guard !targets.isEmpty else { return 0 }

        emit(OfflineDownloadProgress(
            phase: .downloadingContent,
            postsFetched: postsFetched,
            totalPosts: totalPosts,
            itemsCompleted: 0
        ))

        let imageService = imageService
        var completed = 0

        await withTaskGroup(of: Void.self) { group in
            var iterator = targets.makeIterator()
            var inFlight = 0

            /// Seed up to `contentConcurrency` units, then refill as each unit
            /// finishes — a sliding window that keeps at most N requests open.
            func addNextIfPossible() {
                guard !Task.isCancelled, let target = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    await Self.processTarget(
                        target,
                        lemmyService: lemmyService,
                        commentSort: commentSort,
                        imageService: imageService
                    )
                }
            }

            for _ in 0..<min(Self.contentConcurrency, targets.count) {
                addNextIfPossible()
            }

            while inFlight > 0 {
                await group.next()
                inFlight -= 1
                completed += 1
                emit(OfflineDownloadProgress(
                    phase: .downloadingContent,
                    postsFetched: postsFetched,
                    totalPosts: totalPosts,
                    itemsCompleted: completed
                ))
                addNextIfPossible()
            }
        }

        return completed
    }

    /// Best-effort predownload of one post's content: its comment tree, then its
    /// thumbnail and full image. Every failure is swallowed (`try?` / draining
    /// the image stream regardless of outcome) so one bad post never aborts the
    /// download.
    private static func processTarget(
        _ target: OfflineDownloadTarget,
        lemmyService: any LemmyServiceType,
        commentSort: Components.Schemas.CommentSortType,
        imageService: any ImageServiceType
    ) async {
        if Task.isCancelled { return }

        // Comments first: persisted to GRDB so post-detail renders offline.
        // The DB stores server ids as Int64; the API id type is narrower
        // (Int32), so convert at the call boundary like the other call sites.
        try? await lemmyService.fetchComments(
            serverPostId: Components.Schemas.PostID(target.serverPostId),
            sortType: commentSort
        )

        if Task.isCancelled { return }

        if let thumbnailUrl = target.thumbnailUrl {
            await drainImageFetch(imageService, url: thumbnailUrl, downsampleTo: thumbnailDownsampleSize)
        }

        if Task.isCancelled { return }

        if let imageUrl = target.imageUrl {
            await drainImageFetch(imageService, url: imageUrl, downsampleTo: fullImageDownsampleSize)
        }
    }

    /// Drive `imageService.fetch(_:downsampleTo:)` to completion so the bytes
    /// land in the durable disk cache. We use `fetch` (not `startPrefetching`,
    /// which is memory-only and doesn't survive relaunch) and consume the whole
    /// stream — the value isn't used here; the side effect (the disk write) is
    /// the point.
    private static func drainImageFetch(
        _ imageService: any ImageServiceType,
        url: URL,
        downsampleTo size: CGSize
    ) async {
        for await _ in imageService.fetch(url, downsampleTo: size) {
            if Task.isCancelled { return }
        }
    }
}
