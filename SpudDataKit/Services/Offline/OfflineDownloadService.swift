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
    private let diagnostics: DiagnosticLogging
    private let pacing: DownloadPacingConfig

    /// Captures an external-link post's target page as a web archive, used only
    /// when a download opts into `archiveLinks`. Optional so a service built
    /// without web-archive support (or a test that doesn't exercise it) simply
    /// skips link capture. The capturer is `@MainActor` + self-serializing, so
    /// even though several `processTarget`s run concurrently (cap
    /// ``contentConcurrency``), their archive captures funnel through it
    /// one-at-a-time — the heavy `WKWebView` work never fans out.
    private let webArchiveCapturer: (any WebArchiveCapturing)?

    /// Durable store for captured web archives (file + index row). Optional for
    /// the same reason as ``webArchiveCapturer`` — a service without link-archive
    /// support has neither.
    private let webArchiveStore: OfflineWebArchiveStore?

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
    /// run. Sized so that even a run that starts on an already-browsed top page,
    /// plus a sprinkle of ranking-churn duplicate pages, still has enough page
    /// budget to reach a large (250 / 500) `maxPosts` target on a healthy feed.
    private static let maxPagesBuffer = 10

    /// Number of *consecutive* feed pages that may add no new posts before the
    /// page loop concludes the feed is exhausted and stops.
    ///
    /// A single no-growth page is NOT a stop signal: the very first
    /// `fetchFeed(pageCursor: nil)` re-fetches the feed's top page, and if the
    /// user had already scrolled the feed those posts are all in it already, so
    /// `appendFeedPage` de-dupes them and the count doesn't grow — a normal,
    /// expected event, not the end of the feed. Likewise Hot/Active ranking
    /// churn can re-serve an already-seen page mid-run. Only when several pages
    /// IN A ROW contribute nothing do we treat the feed as genuinely exhausted.
    /// A page that grows the count resets the counter (see ``fetchPages``).
    static let maxConsecutiveEmptyPages = 3

    /// Hard cap on the number of feed pages a single download will request, scaled
    /// to `maxPosts`. A backstop against a pathological server that keeps handing
    /// back a non-nil cursor while trickling little or no new content: even if the
    /// consecutive-no-growth guard somehow doesn't fire (e.g. the server adds one
    /// new post per page, so no page is ever empty), this guarantees the page loop
    /// terminates.
    ///
    /// Scaled — rather than a fixed 20 — so a larger `maxPosts` (250 / 500) still
    /// gets enough pages to reach its target on a normal feed: at
    /// ``minExpectedPageSize`` posts/page plus ``maxPagesBuffer``, the backstop
    /// comfortably clears the cap for a healthy feed and only bounds a pathological
    /// one. The consecutive-no-growth break (in ``fetchPages``) remains the primary
    /// feed-exhausted guard; this is the secondary, always-terminating one.
    ///
    /// `minExpectedPageSize` is 10 because `LemmyService.fetchFeed` calls
    /// `getPosts` with no explicit `limit`, so Lemmy's server default page size
    /// (10 posts) applies — the backstop must allow at least `maxPosts / 10`
    /// pages, plus the buffer, or a large run would be capped short. (Most
    /// instances actually return more, so this is a conservative floor.)
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

    /// Per-page timeout for a web-archive capture (`archiveLinks` runs). A page
    /// that hasn't finished loading by then is abandoned and skipped — a polite
    /// bound so one slow host can't stall the download, while still allowing a
    /// typical article (with its subresources) time to settle.
    private static let webArchiveCaptureTimeout: TimeInterval = 20

    /// - Parameters:
    ///   - appDatabase: The shared GRDB store.
    ///   - imageService: The image service used to warm post images into the
    ///     durable disk cache.
    ///   - diagnostics: Diagnostic recorder for structured download events.
    ///   - pacing: Request-pacing and retry tunables. Defaults to `.live`
    ///     (200 ms spacing, 4 attempts). Tests inject `.immediate()` to
    ///     eliminate wall-clock waits.
    ///   - webArchiveCapturer: Optional capturer for external-link pages; required
    ///     for `archiveLinks` runs and otherwise unused. `@MainActor`-bound and
    ///     self-serializing.
    ///   - webArchiveStore: Optional durable store for captured archives; paired
    ///     with `webArchiveCapturer` for `archiveLinks` runs.
    public init(
        appDatabase: AppDatabase,
        imageService: any ImageServiceType,
        diagnostics: DiagnosticLogging,
        pacing: DownloadPacingConfig = .live,
        webArchiveCapturer: (any WebArchiveCapturing)? = nil,
        webArchiveStore: OfflineWebArchiveStore? = nil
    ) {
        self.appDatabase = appDatabase
        self.imageService = imageService
        self.diagnostics = diagnostics
        self.pacing = pacing
        self.webArchiveCapturer = webArchiveCapturer
        self.webArchiveStore = webArchiveStore
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
    ///   - archiveLinks: When true, each external-link post's target page is also
    ///     captured as a web archive (best-effort) so it can be read offline.
    ///     Defaults to false — capturing pages is heavier/slower than warming
    ///     images, so it's opt-in. A no-op unless the service was built with a
    ///     ``WebArchiveCapturing`` + ``OfflineWebArchiveStore``. A capture failure
    ///     (load error / timeout) is swallowed like the other per-item work and
    ///     never aborts the run.
    ///   - instance: The Lemmy instance HOST (e.g. `lemmy.world`) this download is
    ///     scoped to. Used only for diagnostic events; pass `nil` when unknown.
    ///   - sanitizeURL: Optional transform applied to a post's external-link URL
    ///     **before** it is captured and stored. This MUST be the same transform
    ///     the open path (`AppService`) applies before looking an archive up
    ///     (`URLSanitizer.sanitize`), so the store key (sanitized) matches the
    ///     lookup key (sanitized). When nil (the default, used by tests that don't
    ///     exercise sanitization) the raw URL is used unchanged. Only the archive
    ///     key is sanitized; the comment/image work uses the post's own URLs and is
    ///     unaffected.
    public nonisolated func download(
        feed: FeedHandle,
        lemmyService: any LemmyServiceType,
        accountId: Int64,
        siteId: Int64,
        commentSort: Components.Schemas.CommentSortType,
        showNsfw: Bool,
        maxPosts: Int = defaultMaxPosts,
        archiveLinks: Bool = false,
        instance: String? = nil,
        sanitizeURL: (@Sendable (URL) -> URL)? = nil
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
                    archiveLinks: archiveLinks,
                    instance: instance,
                    sanitizeURL: sanitizeURL,
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
        archiveLinks: Bool,
        instance: String?,
        sanitizeURL: (@Sendable (URL) -> URL)?,
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

        // Record the wall-clock start so finish/cancelled events can include
        // a duration. Captured before Phase 1 so page-fetch time is included.
        let startedAt = Date()

        // One pacer per run: paces all feed-page fetches and absorbs pushback
        // penalties (429 / 503) by inserting a global cool-down.
        let pacer = RequestPacer(
            minInterval: pacing.minRequestInterval,
            now: pacing.now,
            sleepUntil: pacing.sleepUntil
        )

        // Phase 1: page through the feed, persisting each page to GRDB.
        let postsFetched: Int
        let wasPartial: Bool
        do {
            let result = try await fetchPages(
                feed: feed,
                lemmyService: lemmyService,
                showNsfw: showNsfw,
                maxPosts: maxPosts,
                pacer: pacer,
                instance: instance,
                emit: emit
            )
            postsFetched = result.count
            wasPartial = result.wasPartial
        } catch is CancellationError {
            // Surface however many posts the cancelled page loop had already
            // persisted so the terminal `.cancelled` (and its
            // `fractionCompleted`) reflects real progress rather than snapping
            // back to zero.
            let persisted = appDatabase.offlineFeedPostCountSync(feedKey: feed.feedKey)
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            await diagnostics.record(
                category: .offlineDownload,
                level: .info,
                event: "download.cancelled",
                message: "Download cancelled during page fetch",
                instance: instance,
                metadata: [
                    "reason": "pageFetchCancelled",
                    "durationMs": String(durationMs),
                ]
            )
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
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            await diagnostics.record(
                category: .offlineDownload,
                level: .info,
                event: "download.cancelled",
                message: "Download cancelled after page fetch",
                instance: instance,
                metadata: [
                    "reason": "cancelledAfterFetch",
                    "durationMs": String(durationMs),
                ]
            )
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

        // Emit download.start after Phase 1 when the target count is known.
        await diagnostics.record(
            category: .offlineDownload,
            level: .info,
            event: "download.start",
            message: "Starting content download phase",
            instance: instance,
            metadata: ["targetCount": String(totalPosts)]
        )

        // Phase 3: download per-post content (comments + images, plus an opt-in
        // web archive for external-link posts), best-effort. The aggregate
        // per-item warm-failure counts come back here so the run summary can
        // report them without spamming the curated table with one event per image.
        let (completed, failed, imageWarmFailures, archiveCaptureFailures) = await downloadContent(
            targets: targets,
            lemmyService: lemmyService,
            commentSort: commentSort,
            archiveLinks: archiveLinks,
            sanitizeURL: sanitizeURL,
            postsFetched: postsFetched,
            totalPosts: totalPosts,
            instance: instance,
            pacer: pacer,
            pacing: pacing,
            emit: emit
        )

        if Task.isCancelled {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            await diagnostics.record(
                category: .offlineDownload,
                level: .info,
                event: "download.cancelled",
                message: "Download cancelled during content phase",
                instance: instance,
                metadata: [
                    "reason": "cancelledDuringContent",
                    "durationMs": String(durationMs),
                ]
            )
            emit(OfflineDownloadProgress(
                phase: .cancelled,
                postsFetched: postsFetched,
                totalPosts: totalPosts,
                itemsCompleted: completed
            ))
            return
        }

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        await diagnostics.record(
            category: .offlineDownload,
            level: .info,
            event: "download.finish",
            message: "Download finished",
            instance: instance,
            metadata: [
                "downloadedCount": String(completed),
                "failedCount": String(failed),
                "durationMs": String(durationMs),
                // Curated aggregates: the total per-item image and web-archive
                // warm failures across the whole run. The individual failures are
                // OSLog-only chatter (see `warmImage` / `processTarget`); only
                // these run-level sums land in the durable diagnostic table.
                "imageWarmFailures": String(imageWarmFailures),
                "archiveCaptureFailures": String(archiveCaptureFailures),
            ]
        )

        emit(OfflineDownloadProgress(
            phase: .finished,
            postsFetched: postsFetched,
            totalPosts: totalPosts,
            itemsCompleted: completed,
            warningMessage: wasPartial
                ? "Downloaded \(postsFetched) posts — some of the feed couldn't be reached."
                : nil
        ))
    }

    /// Page through `feed` until the persisted post count reaches `maxPosts`,
    /// the cursor is nil, or the task is cancelled.
    ///
    /// Each page fetch is paced (``RequestPacer/acquire()``) and wrapped in
    /// ``withRetry`` so transient failures (5xx, timeouts) are retried with
    /// jittered exponential back-off. A permanent failure (4xx) is NOT retried:
    ///
    /// - If at least one page has already been persisted (`persistedCount > 0`),
    ///   the loop exits early and returns `(count: persistedCount, wasPartial: true)`.
    ///   The run then finishes as a partial success with a warning message, rather
    ///   than aborting — the user still gets the posts that did land.
    /// - If no page has been persisted yet, the error is rethrown so `run` can
    ///   emit a `.failed` terminal.
    private func fetchPages(
        feed: FeedHandle,
        lemmyService: any LemmyServiceType,
        showNsfw: Bool,
        maxPosts: Int,
        pacer: RequestPacer,
        instance: String?,
        emit: @Sendable (OfflineDownloadProgress) -> Void
    ) async throws -> (count: Int, wasPartial: Bool) {
        emit(OfflineDownloadProgress(phase: .fetchingPosts))

        // Scale the page backstop to the chosen post cap so a larger run still
        // gets enough pages to reach its target on a healthy feed.
        let maxPages = Self.maxPages(forMaxPosts: maxPosts)

        var cursor: String? = nil
        var persistedCount = appDatabase.offlineFeedPostCountSync(feedKey: feed.feedKey)
        var pagesFetched = 0

        // How many consecutive pages have added no new posts. A single
        // no-growth page is expected and harmless (the first
        // `fetchFeed(pageCursor: nil)` re-fetches the top page, which is wholly
        // in the feed already when the user had scrolled before tapping
        // Download; `appendFeedPage` de-dupes it so the count doesn't grow), so
        // we don't stop on it — we only conclude the feed is exhausted after
        // ``maxConsecutiveEmptyPages`` empties IN A ROW.
        var consecutiveEmptyPages = 0

        repeat {
            try Task.checkCancellation()

            // Snapshot the count before this page so we can detect a page that
            // contributed no new posts (all duplicates already in the feed).
            let beforeCount = persistedCount

            // Pace every attempt (first + each retry) inside the operation closure so
            // that retries are also subject to the per-request spacing. A permanent
            // error (4xx) surfaces immediately — `withRetry` rethrows it.
            do {
                let nextCursor = try await withRetry(
                    maxAttempts: pacing.maxRetryAttempts,
                    baseDelay: pacing.retryBaseDelay,
                    maxDelay: pacing.retryMaxDelay,
                    pushbackCooldown: pacing.serverPushbackCooldown,
                    pacer: pacer,
                    sleep: pacing.sleep,
                    jitter: pacing.jitter,
                    onRetry: { [diagnostics, instance] attempt, delay, error in
                        await diagnostics.record(
                            category: .offlineDownload,
                            level: .notice,
                            event: "download.retry",
                            message: "Retrying page fetch (attempt \(attempt))",
                            instance: instance,
                            metadata: [
                                "phase": "page",
                                "attempt": String(attempt),
                                "delayMs": String(Int(delay.asTimeInterval * 1000)),
                                "error": String(describing: error),
                                // Distinguishes a server "slow down" (429 / 503 /
                                // rate-limit) from other transient blips, so the
                                // log viewer can spot rate-limiting at a glance.
                                "pushback": String(isServerPushback(error)),
                            ]
                        )
                    }
                ) {
                    try await pacer.acquire()
                    return try await lemmyService.fetchFeed(
                        feed,
                        pageCursor: cursor,
                        showNsfw: showNsfw
                    )
                }
                pagesFetched += 1

                persistedCount = appDatabase.offlineFeedPostCountSync(feedKey: feed.feedKey)
                emit(OfflineDownloadProgress(phase: .fetchingPosts, postsFetched: persistedCount))

                // Consecutive-no-growth break: a page that upserted only posts
                // already in the feed adds nothing (the already-browsed top page on
                // the first call, an already-populated re-download, ranking-churn
                // duplicates, or a feed with fewer than maxPosts unique posts). One
                // such page is normal — stopping on it was the shipped bug that
                // ended a 500-post download at the ~handful of already-loaded posts.
                // A page that grows the count resets the counter; only when the
                // feed yields nothing new for ``maxConsecutiveEmptyPages`` pages in
                // a row do we treat it as exhausted and stop (otherwise, with a
                // forever-non-nil cursor, the loop would never terminate).
                if persistedCount > beforeCount {
                    consecutiveEmptyPages = 0
                } else {
                    consecutiveEmptyPages += 1
                    guard consecutiveEmptyPages < Self.maxConsecutiveEmptyPages else { break }
                }

                // nil cursor means the server has no more pages.
                guard let nextCursor, !nextCursor.isEmpty else { break }
                cursor = nextCursor

                // Hard page-count backstop: even a server that trickles one new
                // post per page (so the count keeps creeping up and the
                // consecutive-no-growth guard never fires) can't keep the loop alive
                // indefinitely.
                guard pagesFetched < maxPages else { break }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Permanent failure (already rethrown by withRetry after exhausting retries
                // or immediately for a 4xx). If at least one page landed, keep what we have
                // and finish as partial — the user gets partial content rather than nothing.
                if persistedCount > 0 {
                    await diagnostics.record(
                        category: .offlineDownload,
                        level: .notice,
                        event: "download.pageFetchIncomplete",
                        message: "Page fetch failed after \(persistedCount) posts were already saved; finishing partial",
                        instance: instance,
                        metadata: [
                            "persistedCount": String(persistedCount),
                            "error": String(describing: error),
                        ]
                    )
                    return (count: persistedCount, wasPartial: true)
                }
                // Zero posts persisted — nothing useful to return; let run emit .failed.
                throw error
            }
        } while persistedCount < maxPosts

        return (count: persistedCount, wasPartial: false)
    }

    /// Process `targets` through a bounded `TaskGroup` (cap
    /// ``contentConcurrency``). Per post: fetch+persist its comment tree, warm
    /// its thumbnail (and full image, when present) into the durable disk cache,
    /// and — when `archiveLinks` is on and the post is an external link — capture
    /// its target page as a web archive. Every post counts as completed for the
    /// progress UI regardless of per-step errors; a comment-fetch failure is also
    /// counted in the diagnostic `failed` tally and emits a `download.itemFailed`
    /// event. Emits a progress snapshot after each post.
    ///
    /// Returns the total completed and failed counts, plus the run-wide aggregate
    /// per-item warm failures (`imageWarmFailures` = the number of individual
    /// thumbnail/full-image warms that failed for good; `archiveCaptureFailures` =
    /// the number of external-link posts whose web-archive capture returned nil).
    /// These aggregates are surfaced in the `download.finish` summary so the
    /// durable table records the count without one row per image (per-item detail
    /// stays in OSLog — see ``warmImage`` / ``processTarget``).
    ///
    /// The archive capturer is `@MainActor` + self-serializing, so even though up
    /// to ``contentConcurrency`` posts are processed concurrently, their archive
    /// captures funnel through it one-at-a-time (the heavy `WKWebView` work never
    /// fans out).
    private func downloadContent(
        targets: [OfflineDownloadTarget],
        lemmyService: any LemmyServiceType,
        commentSort: Components.Schemas.CommentSortType,
        archiveLinks: Bool,
        sanitizeURL: (@Sendable (URL) -> URL)?,
        postsFetched: Int,
        totalPosts: Int,
        instance: String?,
        pacer: RequestPacer,
        pacing: DownloadPacingConfig,
        emit: @Sendable (OfflineDownloadProgress) -> Void
    ) async -> (completed: Int, failed: Int, imageWarmFailures: Int, archiveCaptureFailures: Int) {
        guard !targets.isEmpty else { return (0, 0, 0, 0) }

        emit(OfflineDownloadProgress(
            phase: .downloadingContent,
            postsFetched: postsFetched,
            totalPosts: totalPosts,
            itemsCompleted: 0
        ))

        let imageService = imageService
        // Carry the recorder into the per-post work so a content-phase retry can
        // record a `download.retry`; captured as a local (like `imageService`)
        // because the `@Sendable` `addTask` closure can't reach `self`.
        let diagnostics = diagnostics
        // Only carry the capturer/store into the per-post work when archiving is
        // requested AND the service was built with them — otherwise leave them
        // nil so `processTarget` skips the capture branch entirely.
        let capturer = archiveLinks ? webArchiveCapturer : nil
        let store = archiveLinks ? webArchiveStore : nil
        let captureTimeout = Self.webArchiveCaptureTimeout
        var completed = 0
        var failed = 0
        // Run-wide sums of the per-item best-effort warm failures. These are the
        // ONLY durable trace of individual image/archive failures — the failures
        // themselves are OSLog-only (see `warmImage` / `processTarget`).
        var imageWarmFailures = 0
        var archiveCaptureFailures = 0

        await withTaskGroup(of: (outcome: TargetOutcome, serverPostId: Int64).self) { group in
            var iterator = targets.makeIterator()
            var inFlight = 0

            /// Seed up to `contentConcurrency` units, then refill as each unit
            /// finishes — a sliding window that keeps at most N requests open.
            func addNextIfPossible() {
                guard !Task.isCancelled, let target = iterator.next() else { return }
                inFlight += 1
                let serverPostId = target.serverPostId
                group.addTask {
                    let outcome = await Self.processTarget(
                        target,
                        lemmyService: lemmyService,
                        commentSort: commentSort,
                        imageService: imageService,
                        webArchiveCapturer: capturer,
                        webArchiveStore: store,
                        captureTimeout: captureTimeout,
                        sanitizeURL: sanitizeURL,
                        pacer: pacer,
                        pacing: pacing,
                        diagnostics: diagnostics,
                        instance: instance
                    )
                    return (outcome: outcome, serverPostId: serverPostId)
                }
            }

            for _ in 0..<min(Self.contentConcurrency, targets.count) {
                addNextIfPossible()
            }

            while inFlight > 0 {
                guard let result = await group.next() else { break }
                inFlight -= 1
                if !Task.isCancelled {
                    // Every post counts as completed for the progress UI — even
                    // a comment-fetch failure (we still warmed images, and the
                    // post-detail will simply have no cached comments). The
                    // `failed` counter is diagnostic-only and is NOT deducted
                    // from `completed`.
                    completed += 1
                    // Image/archive warm failures are independent best-effort
                    // steps, tallied for every finished post regardless of the
                    // comment outcome.
                    imageWarmFailures += result.outcome.imageWarmFailures
                    archiveCaptureFailures += result.outcome.archiveCaptureFailed ? 1 : 0
                    if !result.outcome.commentSucceeded {
                        failed += 1
                        await diagnostics.record(
                            category: .offlineDownload,
                            level: .notice,
                            event: "download.itemFailed",
                            message: "Failed to download content for post",
                            instance: instance,
                            metadata: ["serverPostId": String(result.serverPostId)]
                        )
                    }
                }
                emit(OfflineDownloadProgress(
                    phase: .downloadingContent,
                    postsFetched: postsFetched,
                    totalPosts: totalPosts,
                    itemsCompleted: completed
                ))
                addNextIfPossible()
            }
        }

        return (completed, failed, imageWarmFailures, archiveCaptureFailures)
    }

    /// The per-post result of ``processTarget(_:lemmyService:commentSort:imageService:webArchiveCapturer:webArchiveStore:captureTimeout:sanitizeURL:pacer:pacing:diagnostics:instance:)``.
    ///
    /// Surfaced so the content loop can (a) drive `download.itemFailed` off the
    /// comment outcome, and (b) aggregate the per-item image/archive warm failures
    /// into the run summary. The per-item image and archive failures are
    /// deliberately NOT individual durable events — that would spam the curated
    /// `diagnosticEvent` table with one row per image. They go to OSLog for detail
    /// and are summed into `download.finish`'s `imageWarmFailures` /
    /// `archiveCaptureFailures` metadata instead.
    private struct TargetOutcome {
        /// Whether the comment-tree fetch ultimately succeeded (false = a real
        /// error after retries; drives `download.itemFailed`). A cancelled post
        /// reports `true` — cancellation is not a content failure.
        var commentSucceeded: Bool
        /// How many of this post's image warms (thumbnail + full image) failed for
        /// good after retries. 0, 1, or 2.
        var imageWarmFailures: Int
        /// Whether an attempted web-archive capture returned nil (load error /
        /// timeout). Stays `false` when the archive branch isn't taken at all
        /// (archiving off, no capturer, or not an external-link post).
        var archiveCaptureFailed: Bool
    }

    /// Best-effort predownload of one post's content: its comment tree, then its
    /// thumbnail and full image, then (when requested) a web archive of its
    /// external link. Every step continues regardless of prior failures so all
    /// content is attempted for every post.
    ///
    /// Returns a ``TargetOutcome``: `commentSucceeded` is `true` when the comment
    /// fetch succeeded (or was cancelled), `false` when it threw a real error (the
    /// caller uses this to emit `download.itemFailed`); `imageWarmFailures` and
    /// `archiveCaptureFailed` carry the per-item warm failures the caller sums into
    /// the curated run summary (the individual failures are OSLog-only chatter).
    ///
    /// - Parameters:
    ///   - webArchiveCapturer: When non-nil AND the post has an
    ///     `externalLinkUrl`, the post's link target is captured + stored. Nil
    ///     when `archiveLinks` is off (or the service has no capturer), skipping
    ///     the capture branch.
    ///   - webArchiveStore: Where a captured archive is persisted. Paired with
    ///     `webArchiveCapturer`.
    ///   - captureTimeout: Per-page web-archive capture timeout.
    ///   - sanitizeURL: Applied to the post's `externalLinkUrl` before capture +
    ///     store, so the archive is keyed under the SAME (sanitized) URL the open
    ///     path looks it up by. Nil = use the raw URL unchanged.
    ///   - diagnostics: Recorder used to emit a `download.retry` when the comment
    ///     fetch is retried (content-phase retry visibility). Sendable, so it can
    ///     be captured into this static method's task.
    ///   - instance: The Lemmy instance host for the retry event's `instance`
    ///     field; nil when unknown.
    private static func processTarget(
        _ target: OfflineDownloadTarget,
        lemmyService: any LemmyServiceType,
        commentSort: Components.Schemas.CommentSortType,
        imageService: any ImageServiceType,
        webArchiveCapturer: (any WebArchiveCapturing)?,
        webArchiveStore: OfflineWebArchiveStore?,
        captureTimeout: TimeInterval,
        sanitizeURL: (@Sendable (URL) -> URL)?,
        pacer: RequestPacer,
        pacing: DownloadPacingConfig,
        diagnostics: DiagnosticLogging,
        instance: String?
    ) async -> TargetOutcome {
        // An all-clear outcome, returned at each cancellation checkpoint:
        // cancellation is not a content failure, so nothing is counted against it.
        let allClear = TargetOutcome(commentSucceeded: true, imageWarmFailures: 0, archiveCaptureFailed: false)
        if Task.isCancelled { return allClear }

        // Comments first: persisted to GRDB so post-detail renders offline.
        // The DB stores server ids as Int64; the API id type is narrower
        // (Int32), so convert at the call boundary like the other call sites.
        // A failure is surfaced to the caller for diagnostic purposes but does
        // NOT abort the rest of this post's work — images and web archives are
        // always attempted (best-effort), matching the pre-existing contract.
        // Transient failures are retried before being swallowed; each retry is
        // recorded as a content-phase `download.retry` so the comment-fetch
        // retries are as visible as the page-fetch ones.
        let serverPostId = target.serverPostId
        var commentSucceeded = true
        do {
            try await withRetry(
                maxAttempts: pacing.maxRetryAttempts,
                baseDelay: pacing.retryBaseDelay,
                maxDelay: pacing.retryMaxDelay,
                pushbackCooldown: pacing.serverPushbackCooldown,
                pacer: pacer,
                sleep: pacing.sleep,
                jitter: pacing.jitter,
                onRetry: { [diagnostics, instance, serverPostId] attempt, delay, error in
                    await diagnostics.record(
                        category: .offlineDownload,
                        level: .notice,
                        event: "download.retry",
                        message: "Retrying comment fetch (attempt \(attempt))",
                        instance: instance,
                        metadata: [
                            "phase": "content",
                            "serverPostId": String(serverPostId),
                            "attempt": String(attempt),
                            "delayMs": String(Int(delay.asTimeInterval * 1000)),
                            "error": String(describing: error),
                            "pushback": String(isServerPushback(error)),
                        ]
                    )
                }
            ) {
                try await pacer.acquire()
                try await lemmyService.fetchComments(
                    serverPostId: Components.Schemas.PostID(target.serverPostId),
                    sortType: commentSort
                )
            }
        } catch {
            commentSucceeded = false
        }

        if Task.isCancelled { return allClear }

        // Per-item warm failures are counted locally and returned to the caller,
        // which sums them into the curated `download.finish` summary. The
        // individual failures are OSLog-only chatter (see `warmImage`) — we do NOT
        // emit a durable event per image, which would flood the diagnostic table.
        var imageWarmFailures = 0

        if let thumbnailUrl = target.thumbnailUrl {
            let succeeded = await Self.warmImage(imageService, url: thumbnailUrl, downsampleTo: thumbnailDownsampleSize, pacer: pacer, pacing: pacing)
            if !succeeded { imageWarmFailures += 1 }
        }

        if Task.isCancelled { return allClear }

        if let imageUrl = target.imageUrl {
            let succeeded = await Self.warmImage(imageService, url: imageUrl, downsampleTo: fullImageDownsampleSize, pacer: pacer, pacing: pacing)
            if !succeeded { imageWarmFailures += 1 }
        }

        if Task.isCancelled { return allClear }

        // Web archive last (it's the heaviest, slowest step). Only for
        // external-link posts, and only when archiving was requested. The
        // capturer self-serializes, so concurrent posts queue here rather than
        // launching N web views at once. A nil capture (load error / timeout) is
        // skipped — best-effort, never fatal — but tallied into the run summary.
        var archiveCaptureFailed = false
        if
            let webArchiveCapturer,
            let webArchiveStore,
            let externalLinkUrl = target.externalLinkUrl
        {
            // Key the archive on the SANITIZED URL so the open path — which
            // sanitizes the tapped link before looking it up — finds it. Without
            // this, any URL the sanitizer rewrites would be stored under one key
            // and looked up under another (the archive would never be found).
            let archiveKey = sanitizeURL?(externalLinkUrl) ?? externalLinkUrl
            if let result = await webArchiveCapturer.capture(archiveKey, timeout: captureTimeout) {
                await webArchiveStore.upsertWebArchive(
                    url: archiveKey,
                    postServerId: target.serverPostId,
                    title: result.title,
                    data: result.data
                )
            } else {
                // Per-item chatter: OSLog only, aggregated into the run summary's
                // `archiveCaptureFailures` — never an individual durable event.
                archiveCaptureFailed = true
                logger.debug("Offline web-archive capture failed for \(archiveKey.absoluteString, privacy: .public) (serverPostId \(serverPostId, privacy: .public))")
            }
        }

        return TargetOutcome(
            commentSucceeded: commentSucceeded,
            imageWarmFailures: imageWarmFailures,
            archiveCaptureFailed: archiveCaptureFailed
        )
    }

    /// Thrown when an image stream completes without ever reaching `.ready`
    /// (a transient warm failure). Lets a warm flow through `withRetry`, which
    /// treats it as transient (`OutboxFailureClass.classify` default).
    private enum OfflineImageFetchError: Error { case notReady }

    /// Drive `imageService.fetch(_:downsampleTo:)` to completion so the bytes
    /// land in the durable disk cache. We use `fetch` (not `startPrefetching`,
    /// which is memory-only and doesn't survive relaunch) and consume the whole
    /// stream — the value isn't used here; the side effect (the disk write) is
    /// the point. Throws ``OfflineImageFetchError/notReady`` if the stream ends
    /// without a `.ready` state (image failed), so the caller can retry.
    private static func drainImageFetch(
        _ imageService: any ImageServiceType,
        url: URL,
        downsampleTo size: CGSize
    ) async throws {
        var sawReady = false
        for await state in imageService.fetch(url, downsampleTo: size) {
            try Task.checkCancellation()
            if case .ready = state { sawReady = true }
        }
        if !sawReady { throw OfflineImageFetchError.notReady }
    }

    /// Best-effort image warm: paced + retried (a lower attempt bound, since an
    /// image failure carries no classifiable error), swallowing the final failure
    /// so one bad image never affects the post's completion — matching the
    /// pre-existing best-effort contract.
    ///
    /// Returns `true` when the image ultimately reached the durable disk cache (or
    /// the warm was cancelled — cancellation is not a content failure and must not
    /// count), `false` when it failed for good after exhausting retries. The
    /// caller aggregates these `false`s into the run summary's `imageWarmFailures`.
    /// The individual failure is per-item chatter: it goes to OSLog only, never as
    /// its own durable `diagnosticEvent` (that would flood the curated table with
    /// one row per image).
    private static func warmImage(
        _ imageService: any ImageServiceType,
        url: URL,
        downsampleTo size: CGSize,
        pacer: RequestPacer,
        pacing: DownloadPacingConfig
    ) async -> Bool {
        do {
            try await withRetry(
                maxAttempts: pacing.maxImageRetryAttempts,
                baseDelay: pacing.retryBaseDelay,
                maxDelay: pacing.retryMaxDelay,
                pushbackCooldown: pacing.serverPushbackCooldown,
                pacer: pacer,
                sleep: pacing.sleep,
                jitter: pacing.jitter
            ) {
                try await pacer.acquire()
                try await drainImageFetch(imageService, url: url, downsampleTo: size)
            }
            return true
        } catch is CancellationError {
            // Cancellation is driven by the content loop's own `Task.isCancelled`
            // checks; it is not an image failure, so don't count it.
            return true
        } catch {
            // Best-effort: swallow, but leave an OSLog breadcrumb naming the image
            // so a run's failures are diagnosable without a durable event per image.
            logger.debug("Offline image warm failed for \(url.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
