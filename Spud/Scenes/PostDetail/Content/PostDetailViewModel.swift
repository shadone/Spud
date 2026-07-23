//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Observation
import OSLog
import SpudDataKit

private let logger = Logger.app

/// View-model state for PostDetailViewController. Plain @Observable values
/// driven by GRDB observations. Sort-type changes trigger a re-fetch via
/// LemmyService.
@MainActor
@Observable
final class PostDetailViewModel {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasPreferencesService &
        HasReachabilityMonitor
    typealias Dependencies = OwnDependencies

    @ObservationIgnored
    private let dependencies: OwnDependencies

    @ObservationIgnored
    private let appDatabase: AppDatabase

    @ObservationIgnored
    let serverPostId: Lemmy.PostID

    @ObservationIgnored
    let accountScope: AccountScope

    var accountKeychainId: String {
        accountScope.accountKeychainId
    }

    /// The post-detail header row, published from the GRDB header observation
    /// this view model owns (see ``startObservations()``). The view controller
    /// reacts to changes to re-render the header, rebuild the overflow menu,
    /// re-evaluate unavailability, and refresh the on-screen privacy state. nil
    /// until the first emit (and when the post row is absent from the database).
    private(set) var headerRow: PostDetailHeaderRow?

    /// This post's cross-posts (other posts sharing its link), last harvested
    /// from `PostDetail.crossPosts` on a `fetchPostInfo` fetch and persisted to
    /// the `postCrossPost` junction table. Drives the post-detail
    /// "Cross-posted to N communities" section; empty when the post has none
    /// (or hasn't been fetched with `fetchPostInfo` yet — e.g. opened straight
    /// from an already-mirrored feed row).
    ///
    /// A one-shot read (``refreshCrossPosts()``), not a live GRDB observation:
    /// cross-posts don't change while viewing a post, so it is enough to re-read
    /// once the post's local row resolves (``startObservations()``) and again
    /// after each pull-to-refresh (``refreshPostInfo()``).
    private(set) var crossPosts: [CrossPostSummary] = []

    private(set) var commentSortType: Lemmy.CommentSortType

    /// True while a (non-pull-refresh) comment fetch is in flight. Pull-to-refresh
    /// calls `LemmyService.fetchComments` directly and does not flip this.
    private(set) var isLoadingComments: Bool = false

    /// The classified failure of the most recent (non-pull-refresh) comment
    /// fetch, or nil when the last fetch succeeded (or none has run). Drives the
    /// inline "couldn't load comments (offline)" state via
    /// ``CommentsBackground/decide(isLoadingComments:hasCompletedFetch:hasComments:fetchError:)``;
    /// cleared the moment a fetch starts so the failed state never lingers over a
    /// retry's skeleton. A failure only surfaces when there are no comments to
    /// show — once any comments are loaded the list stays and pull-to-refresh
    /// failures are surfaced as a toast instead.
    private(set) var commentFetchError: LoadFailure?

    /// True when the last comment fetch stopped with pages the reader can still
    /// ask for. Drives the terminal "Load more comments" row. Only
    /// `.pageBudgetExhausted` sets it: a failed page is a shortfall to report,
    /// not a cursor to resume from.
    private(set) var hasOutstandingCommentPages = false

    /// Monotonically incremented -- never merely set -- each time a winning
    /// (non-cancelled) comment fetch ends `.partial(.pageFetchFailed)`: some
    /// pages landed and a later one did not. The view controller observes
    /// this directly (`ObservationStream.values(of:)`, matching every other
    /// observation loop in that file) and toasts on each increase; see
    /// `PostDetailViewController.startPartialCommentLoadFailureObservation()`.
    ///
    /// Deliberately a plain `@Observable` counter, NOT `@ObservationIgnored`,
    /// and NOT a one-shot read-and-clear flag. The prior design used an
    /// `@ObservationIgnored` bool consumed by an explicit check planted after
    /// every VC-side `await` of a fetch, plus a "backstop" hung off the
    /// `commentsRevision` observation loop for the two fetches with no such
    /// await (the initial load and the composer-success refresh). That
    /// backstop could not work: `@ObservationIgnored` means setting the flag
    /// cannot itself wake the loop, and a later-page fetch failure does not
    /// import (so `commentsRevision` never bumps after it) -- so by the time
    /// the flag flips, the loop has already run its last iteration for the
    /// final successful page and sits blocked awaiting a revision that will
    /// never come. That silently ate the single most common trigger: a post
    /// whose first page succeeds and a later page fails. A monotonic,
    /// observation-tracked counter has no such blind spot -- ANY entry point
    /// that bumps it wakes the observer, including ones with no VC-side await
    /// to hang a check off of. Do not reintroduce a one-shot flag here.
    private(set) var partialCommentLoadFailureRevision = 0

    /// The full, ordered comment tree as last emitted by the GRDB observation.
    /// Collapse is computed against this; it is never mutated by collapse.
    ///
    /// Deliberately `@ObservationIgnored`: the view controller recomputes the
    /// visible tree from this on every collapse toggle, and if reads of it
    /// invalidated observers, each collapse would spuriously re-run the whole
    /// snapshot/prewarm pipeline. Because it is invisible to observation, a
    /// separate published ``commentsRevision`` counter is the explicit signal
    /// that a fresh DB tree landed.
    @ObservationIgnored
    private(set) var orderedComments: [PostDetailCommentRow] = []

    /// Element-id -> comment row lookup for the current tree, rebuilt in the same
    /// synchronous turn as ``orderedComments`` inside ``updateOrderedComments(_:)``.
    /// The view controller resolves a tapped/collapsed/permalink element id
    /// through this instead of scanning ``orderedComments``. Kept on the view
    /// model (not the view controller) so it and ``orderedComments`` can never
    /// drift: an interleaved snapshot apply during a reaction suspension always
    /// sees a lookup consistent with the tree it renders.
    ///
    /// Deliberately `@ObservationIgnored` for the same reason as
    /// ``orderedComments``: it is a derived view of the tree, and reads of it must
    /// not invalidate observers on every collapse toggle. The published
    /// ``commentsRevision`` counter is the DB-emit signal.
    @ObservationIgnored
    private(set) var commentRowsByElementId: [Int64: PostDetailCommentRow] = [:]

    /// Monotonic per-emit signal for the comments observation. Bumped exactly
    /// once each time the GRDB comment tree is delivered — after
    /// ``updateOrderedComments(_:)`` has stored the new tree. The view
    /// controller keys its comment reaction pipeline (lookup rebuild, body
    /// prewarm, snapshot apply, permalink scroll, one-shot fetch kick) on this,
    /// since ``orderedComments`` is `@ObservationIgnored` and cannot serve as an
    /// observation trigger. Starts at 0 (nothing emitted yet); the reaction loop
    /// ignores that initial value and acts only on the increments. Collapse
    /// toggles never touch it — only a DB emit does.
    private(set) var commentsRevision: Int = 0

    /// The post's pending / failed outbound comment rows (status != draft) for
    /// the backing account, published from the GRDB outbound observation this
    /// view model owns (see ``startObservations()``). The view controller reacts
    /// to changes and re-applies the comment snapshot so a locally-composed
    /// comment appears inline while sending and flips to a normal comment (its
    /// outbound row is deleted on success, dropping the overlay node) once the
    /// server confirms. Draft rows are filtered out here so the view controller
    /// never sees them. Keyed on ``serverPostId`` in the observation, so — unlike
    /// the comment observation — it works even before the post is mirrored.
    private(set) var pendingOutboundComments: [OutboundContentRecord] = []

    /// Element ids of comments whose subtrees are currently collapsed. Pure
    /// view-layer state — no API or database involvement.
    @ObservationIgnored
    private(set) var collapsedElementIds: Set<Int64> = []

    /// Element ids of "load more" rows with a fetch in flight. Reconciled against the live tree in
    /// `updateOrderedComments` (a successful splice removes the placeholder element, so its id
    /// disappears and the flag auto-clears); a failure is cleared explicitly by the view controller.
    @ObservationIgnored
    private(set) var loadingMoreElementIds: Set<Int64> = []

    /// The `lastOpenedAt` from before this visit, used to flag comments
    /// published since. nil on a first-ever visit (nothing is "new"). Set by
    /// ``recordVisit(keychainId:serverPostId:postRowId:)`` during observation
    /// bring-up.
    @ObservationIgnored
    var previousVisitAt: Date?

    /// The current account's server person id, used to exclude the user's own
    /// comments from the new-comment delta. nil when signed out.
    @ObservationIgnored
    var currentAccountPersonId: Int64?

    /// Which comments are new since `previousVisitAt`. Recomputed on every
    /// comment-tree snapshot. Observable so the header count updates.
    private(set) var newCommentState: NewCommentState.Result =
        .init(newElementIds: [], firstNewElementId: nil)

    /// A test-injected override for the action-dispatch seam, or nil in
    /// production (where ``lemmy`` builds the live adapter on demand).
    @ObservationIgnored
    private let injectedLemmy: (any PostDetailLemmyServicing)?

    /// The seam through which every non-comment-fetch PostDetail action reaches
    /// the account's `LemmyService`. In production it wraps `accountScope`'s live
    /// `LemmyService`, resolved *at call time* — matching both the pre-refactor
    /// call sites (which read `accountScope.lemmyService` per call) and
    /// `AccountScope`'s "resolve live on each read" contract, and so a
    /// fetch-only test fixture never forces the account lookup. SpudTests inject
    /// a recording double via `init(lemmy:)`. Comment fetching keeps its own
    /// `fetchCommentsOperation` closure seam — the two are deliberately separate
    /// (see `PostDetailLemmyServicing`).
    private var lemmy: any PostDetailLemmyServicing {
        injectedLemmy ?? PostDetailLemmyServiceAdapter(lemmyService: accountScope.lemmyService)
    }

    /// - Parameter maxPages: forwarded to `LemmyService.fetchComments(maxPages:)`
    ///   as-is — see ``commentPageBudgetAttempt`` for who computes it.
    @ObservationIgnored
    private let fetchCommentsOperation: @MainActor (Lemmy.CommentSortType, Int) async throws -> CommentFetchCompletion

    /// How many page-budget "attempts" have been spent on the CURRENT
    /// post+sort comment listing: 1 for an ordinary fetch, incremented once
    /// per "Load more comments" tap so each tap's bound
    /// (``LemmyService/maxCommentPages`` * this) is strictly larger than the
    /// last — otherwise every tap would re-walk the identical first N pages
    /// and the terminal row could never clear (the defect this exists to
    /// fix). Reset to 1 by every FRESH fetch — ``fetchComments()`` (initial
    /// load, sort change, retry) and ``refreshComments()`` (pull-to-refresh)
    /// — so an inflated bound never bleeds into an unrelated listing.
    /// ``loadMoreCommentPages()`` is the only place that increments it
    /// without resetting.
    @ObservationIgnored
    private var commentPageBudgetAttempt = 1

    /// The seam through which ``loadMoreReplies(elementId:parentServerId:)`` reaches
    /// `LemmyService.fetchMoreComments`. In production it wraps `accountScope`'s live
    /// `LemmyService`, resolved at call time (matching ``fetchCommentsOperation``'s
    /// contract). SpudTests inject a recording/throwing closure directly.
    @ObservationIgnored
    private let fetchMoreCommentsOperation: @MainActor (Int64, Lemmy.CommentSortType) async throws -> Void

    @ObservationIgnored
    private var fetchTask: Task<Void, Never>?

    /// The resolved local `post` row id for the backing account, set during
    /// ``startObservations()`` bring-up. nil until resolved (and when the post
    /// is not yet mirrored). Read by the view controller to start the comment
    /// observation against the same row.
    @ObservationIgnored
    private(set) var postRowId: Int64?

    /// The live GRDB header observation feeding ``headerRow``. Owned here so it
    /// stops on an explicit ``stopObservations()`` / task cancel. (Each
    /// observation task binds a strong `self` for the whole `for await` loop, so
    /// the view model cannot deinit while one is still running — a
    /// deinit-while-observing can't happen; the `deinit` cancel is belt-and-braces
    /// cleanup for the already-stopped case.)
    @ObservationIgnored
    private var headerObservationTask: Task<Void, Never>?

    /// The live GRDB comment-tree observation feeding ``orderedComments`` +
    /// ``commentsRevision``. Owned here (like the header task) so it stops on an
    /// explicit stop / cancel; restarted on a sort change (see
    /// ``restartComments(sortType:)``).
    @ObservationIgnored
    private var commentObservationTask: Task<Void, Never>?

    /// The live GRDB outbound-comment observation feeding
    /// ``pendingOutboundComments``. Owned here (like the header task) so it stops
    /// on an explicit stop / cancel. Keyed on ``serverPostId``, so it is started
    /// unconditionally (independent of the ``postRowId`` gate the header /
    /// comment observations sit behind).
    @ObservationIgnored
    private var outboundObservationTask: Task<Void, Never>?

    /// Subscription to the account's composer success stream. Fires a comment
    /// re-fetch when a comment is successfully created (or edited) on THIS post,
    /// so a just-sent comment becomes visible without a manual pull-to-refresh.
    ///
    /// Started LAZILY, the first time the user presents the reply composer from
    /// this post detail (see ``beginComposerSuccessObservationIfNeeded()``) — NOT
    /// in ``startObservations()``. Reading `composerSuccessEvents()` resolves the
    /// account's `ComposerOutboxService`, which starts (and drains) the outbox as
    /// a side effect; gating it behind an explicit intent-to-compose keeps merely
    /// viewing a post from ever kicking the outbox.
    @ObservationIgnored
    private var composerSuccessObservationTask: Task<Void, Never>?

    /// True while a composer-success-triggered refresh is in flight. Coalesces a
    /// burst of rapid sends: a further success while one is running sets
    /// ``pendingComposerSuccessRefresh`` instead of starting a second concurrent
    /// `getComments`.
    @ObservationIgnored
    private var isRefreshingAfterComposerSuccess = false

    /// Set when a composer success arrives while a refresh is already running, so
    /// exactly one trailing refresh runs afterwards (picking up a comment whose
    /// success landed after the in-flight fetch was issued).
    @ObservationIgnored
    private var pendingComposerSuccessRefresh = false

    private var alertService: AlertServiceType {
        dependencies.alertService
    }

    private var reachabilityMonitor: ReachabilityMonitoring {
        dependencies.reachabilityMonitor
    }

    init(
        serverPostId: Lemmy.PostID,
        accountScope: AccountScope,
        appDatabase: AppDatabase,
        dependencies: Dependencies,
        lemmy: (any PostDetailLemmyServicing)? = nil,
        fetchCommentsOperation: (@MainActor (Lemmy.CommentSortType, Int) async throws -> CommentFetchCompletion)? = nil,
        fetchMoreCommentsOperation: (@MainActor (Int64, Lemmy.CommentSortType) async throws -> Void)? = nil
    ) {
        self.dependencies = dependencies
        self.appDatabase = appDatabase
        self.serverPostId = serverPostId
        self.accountScope = accountScope
        injectedLemmy = lemmy
        commentSortType = dependencies.preferencesService.defaultCommentSortType
        self.fetchCommentsOperation = fetchCommentsOperation ?? { sortType, maxPages in
            try await accountScope.lemmyService
                .fetchComments(serverPostId: serverPostId, sortType: sortType, maxPages: maxPages)
        }
        self.fetchMoreCommentsOperation = fetchMoreCommentsOperation ?? { parentServerId, sortType in
            try await accountScope.lemmyService.fetchMoreComments(
                serverPostId: serverPostId,
                parentServerId: parentServerId,
                sortType: sortType
            )
        }
    }

    deinit {
        headerObservationTask?.cancel()
        commentObservationTask?.cancel()
        outboundObservationTask?.cancel()
        composerSuccessObservationTask?.cancel()
    }

    // MARK: - Observation bring-up

    /// Starts the view model's data observations: resolves the post's local row
    /// id, records this visit (seeding the new-comment delta inputs), and starts
    /// the live GRDB header observation that publishes ``headerRow``. When the
    /// post is not yet mirrored the row id is unresolved, so this triggers an
    /// initial comment fetch (which dual-writes the post) and leaves ``postRowId``
    /// nil; the caller re-starts observations after the fetch. Cancels any prior
    /// observation first so it is safe to call on a view-model reuse / restart.
    func startObservations() {
        stopObservations()

        // The outbound (pending / failed) overlay is keyed on `serverPostId`, so
        // it works even before the post is mirrored — start it independently of
        // the `postRowId` gate the header / comment observations sit behind.
        startOutboundObservation()

        let keychainId = accountKeychainId
        let serverPostId = Int64(serverPostId)

        guard let postRowId = appDatabase.postRowIdSync(
            forKeychainId: keychainId,
            serverPostId: serverPostId
        ) else {
            // Post not yet mirrored; trigger a comment fetch which will
            // dual-write everything we need, then the observation can bring rows
            // in on the next start.
            postRowId = nil
            didPrepareObservation(numberOfFetchedComments: 0)
            return
        }

        self.postRowId = postRowId
        recordVisit(keychainId: keychainId, serverPostId: serverPostId, postRowId: postRowId)
        refreshCrossPosts()

        headerObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await row in appDatabase.observePostDetailHeader(postRowId: postRowId) {
                if Task.isCancelled { break }
                headerRow = row
            }
        }

        startCommentObservation(postRowId: postRowId, sortType: commentSortType.rawValue)
    }

    /// Cancels the view model's data observations. Called on reuse / restart and
    /// from `deinit`.
    func stopObservations() {
        headerObservationTask?.cancel()
        headerObservationTask = nil
        commentObservationTask?.cancel()
        commentObservationTask = nil
        outboundObservationTask?.cancel()
        outboundObservationTask = nil
        composerSuccessObservationTask?.cancel()
        composerSuccessObservationTask = nil
    }

    /// Starts (or restarts) the GRDB outbound-comment observation for this post +
    /// account. Each emit publishes the non-draft rows into
    /// ``pendingOutboundComments`` (drafts are unsent compose-bar text and never
    /// shown inline). Cancels any prior outbound task first.
    private func startOutboundObservation() {
        outboundObservationTask?.cancel()
        let serverPostId = Int64(serverPostId)
        let keychainId = accountKeychainId
        outboundObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await rows in appDatabase.observeOutboundComments(
                postServerId: serverPostId,
                accountKeychainId: keychainId
            ) {
                if Task.isCancelled { break }
                pendingOutboundComments = rows.filter { $0.status != OutboundStatus.draft.rawValue }
            }
        }
    }

    /// Starts the composer-success subscription the first time the user shows an
    /// intent to compose on this post (the reply composer is presented). Idempotent
    /// — the guard means repeated presents only subscribe once, and the live task
    /// spans the view model's lifetime (cancelled in ``stopObservations()`` /
    /// `deinit`). The view controller calls this at composer-present.
    ///
    /// When a comment is successfully created or edited on THIS post, the handler
    /// re-fetches the comment tree so the new comment becomes visible. This closes
    /// the gap left by the optimistic composing flow: the composer outbox deletes
    /// the optimistic overlay on send success, and the single-comment success
    /// mirror (`upsertComment(from:)`) inserts a bare `CommentRecord` with NO
    /// `commentElement` row — so the just-sent comment is invisible to
    /// `observePostDetailComments` (which renders only `commentElement` rows) until
    /// a full `getComments` rebuilds the elements. The re-fetch
    /// (``refreshComments()``, the same path pull-to-refresh uses) does exactly
    /// that, and the paired ``refreshPostInfo()`` re-syncs the header comment count.
    ///
    /// Filtered to `.comment`-kind successes whose ``ComposerOutboxSuccess/postServerId``
    /// matches this post, so unrelated composes (a post create, a DM, or a comment
    /// on a different open post-detail) never trigger a refetch here.
    ///
    /// Subscribing at composer-PRESENT (not at submit) ensures we are already
    /// listening before the send can complete, so a fast success is never missed;
    /// and confining the subscription to an explicit intent-to-compose — rather
    /// than ``startObservations()`` — keeps merely viewing a post from resolving
    /// (and thereby starting/draining) the account's composer outbox.
    func beginComposerSuccessObservationIfNeeded() {
        guard composerSuccessObservationTask == nil else { return }
        let serverPostId = Int64(serverPostId)
        composerSuccessObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await success in await accountScope.composerSuccessEvents() {
                if Task.isCancelled { break }
                guard success.kind == .comment, success.postServerId == serverPostId else { continue }
                await refreshAfterComposerSuccess()
            }
        }
    }

    /// Re-fetches this post's comments (and best-effort header counters) after a
    /// comment success on this post. Reuses the pull-to-refresh seams
    /// (``refreshComments()`` / ``refreshPostInfo()``) so it flows through the
    /// same `getComments` rebuild + GRDB observations the manual refresh does —
    /// without entering the ``fetchComments()`` cancel-and-replace state machine
    /// (no skeleton flash on a background auto-refresh). Errors are swallowed:
    /// the comment is already sent, and a failed auto-refresh simply leaves the
    /// pre-fix behaviour (a manual pull-to-refresh still surfaces the comment).
    ///
    /// Coalesced: while a refresh is running, a further success sets a trailing
    /// flag so exactly one more refresh runs afterwards, collapsing a burst of
    /// rapid sends into at most one in-flight plus one queued `getComments`.
    private func refreshAfterComposerSuccess() async {
        guard !isRefreshingAfterComposerSuccess else {
            pendingComposerSuccessRefresh = true
            return
        }
        isRefreshingAfterComposerSuccess = true
        defer { isRefreshingAfterComposerSuccess = false }
        repeat {
            pendingComposerSuccessRefresh = false
            try? await refreshComments()
            try? await refreshPostInfo()
        } while pendingComposerSuccessRefresh
    }

    /// Starts (or restarts) the GRDB comment-tree observation for `postRowId` +
    /// `sortType`. Each emit stores the new tree via ``updateOrderedComments(_:)``
    /// then bumps ``commentsRevision`` so the view controller reacts. Cancels any
    /// prior comment task first.
    private func startCommentObservation(postRowId: Int64, sortType: String) {
        commentObservationTask?.cancel()
        commentObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await rows in appDatabase.observePostDetailComments(
                postRowId: postRowId,
                sortType: sortType
            ) {
                if Task.isCancelled { break }
                updateOrderedComments(rows)
                commentsRevision += 1
            }
        }
    }

    /// Applies a new comment sort and restarts the comment observation with the
    /// new ordering. Mirrors the view controller's former restart: the post may
    /// have become mirrored since open, so the local row id is re-resolved here
    /// (rather than reusing ``postRowId``) and the observation only restarts once
    /// it resolves. The caller separately kicks a fetch (cancel-and-replace) to
    /// pull the newly-sorted tree from the server.
    func restartComments(sortType: Lemmy.CommentSortType) {
        setCommentSortType(sortType)
        guard let postRowId = appDatabase.postRowIdSync(
            forKeychainId: accountKeychainId,
            serverPostId: Int64(serverPostId)
        ) else { return }
        self.postRowId = postRowId
        startCommentObservation(postRowId: postRowId, sortType: sortType.rawValue)
    }

    /// Records this post-detail visit in the local interaction log and seeds
    /// the new-comment delta inputs. The prior `lastOpenedAt` is read
    /// synchronously *before* the async write overwrites it, so the first
    /// comment snapshot already reflects the correct "new since last visit" set.
    /// Recording is independent of `markPostsRead` (that preference only gates
    /// the server `markAsRead` round-trip).
    private func recordVisit(keychainId: String, serverPostId: Int64, postRowId: Int64) {
        previousVisitAt = appDatabase.lastOpenedAtSync(
            forKeychainId: keychainId,
            serverPostId: serverPostId
        )
        currentAccountPersonId = appDatabase.accountPersonServerIdSync(
            forKeychainId: keychainId
        )

        let snapshotAndCount = appDatabase.postInteractionSnapshotSync(postRowId: postRowId)
        Task { @MainActor [appDatabase] in
            FunStats.record(.postsOpened)
            try? await appDatabase.recordPostOpened(
                accountKeychainId: keychainId,
                serverPostId: serverPostId,
                commentCount: snapshotAndCount?.commentCount,
                snapshot: snapshotAndCount?.snapshot
            )
        }
    }

    func setCommentSortType(_ sortType: Lemmy.CommentSortType) {
        commentSortType = sortType
    }

    /// One-shot refresh of ``crossPosts`` from the `postCrossPost` junction.
    /// Called when the post's local row resolves (``startObservations()``) and
    /// after ``refreshPostInfo()`` lands fresh cross-post data from the server.
    private func refreshCrossPosts() {
        crossPosts = appDatabase.crossPostSummariesSync(
            forKeychainId: accountKeychainId,
            serverPostId: Int64(serverPostId)
        )
    }

    // MARK: - Collapse state (view-layer)

    /// Stores the latest ordered comment tree. Drops any collapsed ids that no
    /// longer exist in the new tree so stale state can't accumulate.
    ///
    /// Rebuilds ``commentRowsByElementId`` in the same synchronous turn, so the
    /// element-id lookup and ``orderedComments`` are always mutually consistent
    /// (never observable in a state where one reflects a newer tree than the
    /// other). Does NOT bump ``commentsRevision`` — the observation loop bumps it
    /// once, immediately after this returns.
    func updateOrderedComments(_ rows: [PostDetailCommentRow]) {
        orderedComments = rows
        commentRowsByElementId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let existingIds = Set(rows.map(\.id))
        collapsedElementIds.formIntersection(existingIds)
        loadingMoreElementIds.formIntersection(existingIds)
        newCommentState = NewCommentState.compute(
            orderedComments: rows,
            previousVisitAt: previousVisitAt,
            currentAccountPersonId: currentAccountPersonId
        )
    }

    /// Toggles the collapsed state of the comment element `elementId`.
    /// - Returns: `true` if the comment is now collapsed, `false` if expanded.
    @discardableResult
    func toggleCollapse(elementId: Int64) -> Bool {
        if collapsedElementIds.contains(elementId) {
            collapsedElementIds.remove(elementId)
            return false
        } else {
            collapsedElementIds.insert(elementId)
            return true
        }
    }

    func isCollapsed(elementId: Int64) -> Bool {
        collapsedElementIds.contains(elementId)
    }

    // MARK: - Load more replies

    func isLoadingMore(elementId: Int64) -> Bool {
        loadingMoreElementIds.contains(elementId)
    }

    func markLoadingMore(elementId: Int64) {
        loadingMoreElementIds.insert(elementId)
    }

    func clearLoadingMore(elementId: Int64) {
        loadingMoreElementIds.remove(elementId)
    }

    /// Fetches and splices the missing replies under `parentServerId`. The caller (the view
    /// controller) marks the row loading and reconfigures the cell before calling this, and on a
    /// thrown error clears the flag + reconfigures + shows a toast. On success the comment
    /// observation emits the spliced tree and the row is replaced.
    ///
    /// - Parameter elementId: Not read by this method's body; kept for API symmetry with
    ///   ``markLoadingMore(elementId:)`` / ``clearLoadingMore(elementId:)`` (the caller already keys
    ///   its mark/clear/reconfigure on it) and for potential future use here (e.g. logging).
    func loadMoreReplies(elementId: Int64, parentServerId: Int64) async throws {
        try await fetchMoreCommentsOperation(parentServerId, commentSortType)
    }

    /// Resumes a comment listing that stopped at the page budget, from the
    /// terminal "Load more comments" row. Reuses the ordinary fetch path, but
    /// with an ENLARGED page bound rather than a persisted cursor:
    /// `LemmyService.fetchComments` always restarts its walk at page 1 (see
    /// its doc comment) because `AppDatabase.upsertComments`'s FINAL call for
    /// the walk — after every page-by-page call, which is additive and never
    /// deletes — treats the whole accumulated set as the FULL desired state
    /// for `(post, sortType)` and deletes any stored element not in it —
    /// resuming from a persisted cursor would seed that accumulated set with
    /// only the tail, so the final call would delete every earlier page's
    /// rows. Re-walking from page 1 with a bigger budget on every tap is
    /// strictly more expensive, but it keeps that full-set reconciliation
    /// correct with no importer surgery for what is a rare deep-thread case.
    /// ``commentPageBudgetAttempt`` grows the bound by another
    /// `LemmyService.maxCommentPages` pages on every tap (10, 20, 30, ...),
    /// so each tap makes real forward progress instead of re-fetching the
    /// identical first N pages forever.
    func loadMoreCommentPages() async {
        commentPageBudgetAttempt += 1
        await fetchComments(maxPages: LemmyService.maxCommentPages * commentPageBudgetAttempt)
    }

    // MARK: - New-comment delta (view-layer)

    /// Number of comments new since the user's last visit.
    var newCommentCount: Int {
        newCommentState.count
    }

    /// Whether the comment element `elementId` is new since the last visit.
    func isNewComment(elementId: Int64) -> Bool {
        newCommentState.newElementIds.contains(elementId)
    }

    /// The element id of the first (lowest-position) new comment, for
    /// "jump to first new". nil when there are none.
    var firstNewCommentElementId: Int64? {
        newCommentState.firstNewElementId
    }

    /// Element ids of the new comments in display order (the order they appear
    /// in the current tree). Powers the "Next new" jump. Empty on a first visit.
    var orderedNewCommentElementIds: [Int64] {
        let newIds = newCommentState.newElementIds
        guard !newIds.isEmpty else { return [] }
        return orderedComments.map(\.id).filter { newIds.contains($0) }
    }

    /// The visible comment rows + per-parent hidden-descendant counts, given
    /// the current collapsed set. Pure; cheap to recompute on every snapshot.
    func visibleCommentTree() -> CommentCollapseState.VisibleTree {
        CommentCollapseState.visibleTree(
            orderedComments: orderedComments,
            collapsedIds: collapsedElementIds,
            newElementIds: newCommentState.newElementIds
        )
    }

    /// Expands every currently-collapsed ancestor of `elementId` so the comment
    /// becomes visible. Returns `true` if the collapsed set changed (the caller
    /// rebuilds the snapshot before scrolling). Idempotent: an already-visible
    /// target changes nothing and returns `false`.
    @discardableResult
    func expandAncestors(toReveal elementId: Int64) -> Bool {
        let ancestors = CommentCollapseState.collapsedAncestors(
            of: elementId,
            in: orderedComments,
            collapsedIds: collapsedElementIds
        )
        guard !ancestors.isEmpty else { return false }
        collapsedElementIds.subtract(ancestors)
        return true
    }

    func didPrepareObservation(numberOfFetchedComments: Int) {
        Task { await fetchComments() }
    }

    /// Fetches this post's comments at the current sort type, using the base
    /// page budget. The entry point for every FRESH (non-continuation) fetch
    /// — initial load, sort change, and Retry from the inline failed state —
    /// so it resets ``commentPageBudgetAttempt`` to 1: only
    /// ``loadMoreCommentPages()`` should ever ask for more than the base
    /// budget.
    ///
    /// Also clears a stale ``hasOutstandingCommentPages`` the instant the
    /// fetch starts, synchronously — before the tree observation can re-emit
    /// an empty snapshot for the new sort. Without this, a sort change while
    /// the terminal "Load more comments" row was showing left the flag true
    /// through the whole re-walk, so the (still tappable) row rendered
    /// underneath the fresh skeleton until the walk finished. This is
    /// deliberately NOT done in the shared ``fetchComments(maxPages:)`` below
    /// — ``loadMoreCommentPages()`` also funnels through it, and clearing the
    /// flag there would flicker the row away and back on every tap.
    func fetchComments() async {
        commentPageBudgetAttempt = 1
        hasOutstandingCommentPages = false
        await fetchComments(maxPages: LemmyService.maxCommentPages)
    }

    private func fetchComments(maxPages: Int) async {
        // Cancel-and-replace: a new fetch (e.g. a sort change, or a Retry from
        // the inline failed state) supersedes the in-flight one. The flag is set
        // synchronously and only the winning (non-cancelled) task clears it or
        // surfaces an error, so it never flaps and a superseded fetch is silent.
        fetchTask?.cancel()
        isLoadingComments = true
        // Clear any prior failure as the (retry) fetch starts so the inline
        // failed state is replaced by the skeleton, not stacked behind it.
        commentFetchError = nil
        let sortType = commentSortType
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let completion = try await fetchCommentsOperation(sortType, maxPages)
                if !Task.isCancelled {
                    // A successful (winning) load clears any lingering failure so
                    // the empty / comments state can show.
                    commentFetchError = nil
                    hasOutstandingCommentPages = completion == .partial(.pageBudgetExhausted)
                    if completion == .partial(.pageFetchFailed) {
                        partialCommentLoadFailureRevision += 1
                    }
                }
            } catch is CancellationError {
                // Superseded — leave the flag to the winning fetch.
            } catch {
                // The production `fetchCommentsOperation` (LemmyService.fetchComments)
                // wraps all underlying errors — including cancellation — as a domain
                // error, so `catch is CancellationError` only fires for direct /
                // seam cancellation. In the production path this `catch` fires instead,
                // and the `!Task.isCancelled` guard below is what silences a superseded
                // fetch. Do NOT remove these guards as "redundant" — they are load-bearing.
                if !Task.isCancelled {
                    // Drive the inline failed state instead of a modal alert: an
                    // inline "couldn't load comments (offline)" surface with a
                    // Retry is better UX than an alert over a misleading empty
                    // state. The view controller renders it where the empty state
                    // would show, and the failed state takes precedence over
                    // ".empty" when there are no comments to display.
                    commentFetchError = LoadFailure.classify(
                        error,
                        isOnline: reachabilityMonitor.isOnline
                    )
                }
            }
            if !Task.isCancelled {
                isLoadingComments = false
            }
        }
        fetchTask = task
        await task.value
    }

    // MARK: - Data accessors (view controller + its action seams)

    /// The backing account's home-instance actor id (its `ap_id` host), or nil
    /// when signed out / unresolved. Used to build canonical post / comment
    /// share + Handoff URLs. A synchronous DB read, matching the pre-move call
    /// shape at the share / user-activity sites.
    var instanceActorId: String? {
        appDatabase.accountInstanceActorIdSync(forKeychainId: accountKeychainId)
    }

    /// True when `creatorPersonId` matches the backing account's own server
    /// person id. A nil creator — or a signed-out / unresolved account (no own
    /// person) — is never "own". Drives hiding "Report" / "Block" on the user's
    /// own posts and comments, and showing "Edit" / "Delete" instead.
    func isOwnContent(creatorPersonId: Int64?) -> Bool {
        guard let creatorPersonId else { return false }
        guard let own = appDatabase.accountOwnPersonIdsSync(
            forKeychainId: accountKeychainId
        ) else { return false }
        return creatorPersonId == own.serverPersonId
    }

    /// Whether `host` is a known Lemmy instance (present in the explorer
    /// directory). Backs the "Open in Spud" affordance on tapped body-text
    /// links: only a URL whose host classifies as Lemmy content offers in-app
    /// open. A synchronous DB read.
    func isKnownInstance(host: String) -> Bool {
        appDatabase.explorerInstanceSync(baseurl: host) != nil
    }

    /// Mutes `communityActorId` for the backing account until `until` (nil =
    /// forever). Muting is a client-local, timed view concern (not sign-in
    /// gated); this writes the muted-community row synchronously.
    func muteCommunity(communityActorId: String, until: Date?) {
        appDatabase.muteCommunitySync(
            forKeychainId: accountKeychainId,
            communityActorId: communityActorId,
            until: until
        )
    }

    // MARK: - Action dispatch (report)

    /// Reports this post to the moderators with the given `reason`. A thin
    /// forward to the account's `LemmyService` (via the ``lemmy`` seam); the
    /// view controller owns the sign-in gate, reason prompt, haptics, and the
    /// success/error surfaces. Rethrows the service error unchanged.
    func reportPost(reason: String) async throws {
        try await lemmy.reportPost(serverPostId: serverPostId, reason: reason)
    }

    /// Reports the comment `serverCommentId` to the moderators with the given
    /// `reason`. Converts the local `Int64` id to the API `CommentID` here so
    /// the view controller stays free of that conversion. Rethrows the service
    /// error unchanged.
    func reportComment(serverCommentId: Int64, reason: String) async throws {
        try await lemmy.reportComment(
            serverCommentId: Lemmy.CommentID(serverCommentId),
            reason: reason
        )
    }

    // MARK: - Action dispatch (delete / restore)

    /// Deletes or restores the user's OWN comment `serverCommentId`. Converts
    /// the local `Int64` id to the API `CommentID` here so the view controller
    /// stays free of that conversion. Rethrows the service error unchanged.
    func deleteComment(serverCommentId: Int64, deleted: Bool) async throws {
        try await lemmy.deleteComment(
            serverCommentId: Lemmy.CommentID(serverCommentId),
            deleted: deleted
        )
    }

    /// Deletes or restores the user's OWN post `serverPostId`. Rethrows the
    /// service error unchanged.
    func deletePost(serverPostId: Lemmy.PostID, deleted: Bool) async throws {
        try await lemmy.deletePost(serverPostId: serverPostId, deleted: deleted)
    }

    // MARK: - Action dispatch (moderation)

    /// Removes (or restores) `serverPostId` as a moderator/admin, optionally
    /// with a `reason` shown to the author. Rethrows the service error
    /// unchanged.
    func removePost(serverPostId: Lemmy.PostID, removed: Bool, reason: String?) async throws {
        try await lemmy.removePost(serverPostId: serverPostId, removed: removed, reason: reason)
    }

    /// Locks (or unlocks) `serverPostId` as a moderator/admin. Rethrows the
    /// service error unchanged.
    func lockPost(serverPostId: Lemmy.PostID, locked: Bool) async throws {
        try await lemmy.lockPost(serverPostId: serverPostId, locked: locked)
    }

    /// Features (pins) or unfeatures `serverPostId`. `local` pins to the
    /// instance front page (admin-only); otherwise pins to the community.
    /// Rethrows the service error unchanged.
    func featurePost(serverPostId: Lemmy.PostID, featured: Bool, local: Bool) async throws {
        try await lemmy.featurePost(serverPostId: serverPostId, featured: featured, local: local)
    }

    /// Removes (or restores) `serverCommentId` as a moderator/admin, optionally
    /// with a `reason` shown to the author. Converts the local `Int64` id to
    /// the API `CommentID` here so the view controller stays free of that
    /// conversion. Rethrows the service error unchanged.
    func removeComment(serverCommentId: Int64, removed: Bool, reason: String?) async throws {
        try await lemmy.removeComment(
            serverCommentId: Lemmy.CommentID(serverCommentId),
            removed: removed,
            reason: reason
        )
    }

    /// Distinguishes (or undistinguishes) `serverCommentId` as a moderator.
    /// Converts the local `Int64` id to the API `CommentID` here so the view
    /// controller stays free of that conversion. Rethrows the service error
    /// unchanged.
    func distinguishComment(serverCommentId: Int64, distinguished: Bool) async throws {
        try await lemmy.distinguishComment(
            serverCommentId: Lemmy.CommentID(serverCommentId),
            distinguished: distinguished
        )
    }

    /// Bans `serverPersonId` from `communityId` as a moderator/admin. Bakes
    /// `ban: true` — the view controller's ban action only ever bans (there is
    /// no unban entry point in this screen), so it does not need to pass the
    /// flag through. When `removeData` is true, the person's existing content
    /// in the community is also removed. Rethrows the service error unchanged.
    func banFromCommunity(
        communityId: Lemmy.CommunityID,
        serverPersonId: Lemmy.PersonID,
        removeData: Bool,
        reason: String?
    ) async throws {
        try await lemmy.banFromCommunity(
            serverCommunityId: communityId,
            serverPersonId: serverPersonId,
            ban: true,
            removeData: removeData,
            reason: reason
        )
    }

    // MARK: - Action dispatch (pending comments / block)

    /// Retries a previously failed comment composition (send or edit)
    /// identified by `clientToken`. Non-throwing, mirroring the service — a
    /// retry that fails again surfaces later through the composer's own
    /// failure state, not through this call.
    func retryComposition(clientToken: String) async {
        await lemmy.retryComposition(clientToken: clientToken)
    }

    /// Permanently discards the composition identified by `clientToken`.
    /// Non-throwing, mirroring the service.
    func discardComposition(clientToken: String) async {
        await lemmy.discardComposition(clientToken: clientToken)
    }

    /// Blocks `serverPersonId` for the backing account. Bakes `blocked: true`
    /// — the view controller's block action never unblocks from this screen
    /// — and converts the local `Int64` id to the API `PersonID` here so the
    /// view controller stays free of that conversion. Rethrows the service
    /// error unchanged.
    func blockAuthor(serverPersonId: Int64) async throws {
        try await lemmy.setBlocked(
            serverPersonId: Lemmy.PersonID(serverPersonId),
            blocked: true
        )
    }

    // MARK: - Action dispatch (read-path wrappers + comment vote / save)

    /// Marks this post read on the server for the backing account. A thin
    /// forward for its own ``serverPostId``; the view controller owns the
    /// `markPostsRead`-preference gating and the error surface. Rethrows the
    /// service error unchanged.
    func markAsRead() async throws {
        try await lemmy.markAsRead(serverPostId: serverPostId)
    }

    /// Refreshes this post's record (the header counters that only a fresh
    /// `PostView` updates) from the server, for its own ``serverPostId``. Used by
    /// pull-to-refresh alongside a comment reload. Rethrows the service error
    /// unchanged; the view controller deliberately swallows it so a header-counter
    /// refresh failure never masks the comment-load error surface.
    func refreshPostInfo() async throws {
        try await lemmy.fetchPostInfo(serverPostId: serverPostId)
        refreshCrossPosts()
    }

    /// Resolves the backing account's moderation capability from the server and
    /// returns it. A thin forward; the view controller owns the best-effort `try?`
    /// / `.none` fallback and applies the result. Rethrows the service error
    /// unchanged.
    func fetchModerationCapability() async throws -> ModerationCapability {
        try await lemmy.fetchModerationCapability()
    }

    /// Reloads this post's comments from the server at the current
    /// ``commentSortType``, for pull-to-refresh. Deliberately reuses the existing
    /// ``fetchCommentsOperation`` closure seam (NOT the ``lemmy`` protocol seam)
    /// and, matching the pre-refactor direct service call from the view
    /// controller's `reloadAsync`, does NOT enter the ``fetchComments()``
    /// cancel-and-replace state machine (``isLoadingComments`` /
    /// ``commentFetchError`` / ``fetchTask``). Rethrows the fetch error unchanged
    /// so the view controller can surface it with the `.fetchComments` alert tag.
    ///
    /// Resets ``commentPageBudgetAttempt`` to 1 like every other fresh fetch —
    /// a pull-to-refresh must not inherit an inflated bound left over from a
    /// prior "Load more comments" streak.
    ///
    /// Captures the returned completion and updates ``hasOutstandingCommentPages``
    /// from it, mirroring the winning branch of `fetchComments(maxPages:)` --
    /// otherwise the "Load more comments" row goes stale after a refresh: it
    /// lingers when the refreshed walk actually completed the tree, and fails
    /// to appear when the refreshed walk is genuinely partial. Also mirrors that
    /// branch's ``partialCommentLoadFailureRevision`` handling -- a refresh
    /// (pull-to-refresh, or the post-composer-success refresh) can just as
    /// easily lose a later page as the ordinary fetch path can, and the reader
    /// deserves the same toast either way. Guarded by `!Task.isCancelled` for
    /// the same reason as that winning branch: only a completed (non-cancelled)
    /// refresh should write either flag.
    func refreshComments() async throws {
        commentPageBudgetAttempt = 1
        let completion = try await fetchCommentsOperation(commentSortType, LemmyService.maxCommentPages)
        if !Task.isCancelled {
            hasOutstandingCommentPages = completion == .partial(.pageBudgetExhausted)
            if completion == .partial(.pageFetchFailed) {
                partialCommentLoadFailureRevision += 1
            }
        }
    }

    /// Casts (or clears) a vote on the comment `serverCommentId` for the backing
    /// account. Converts the local `Int64` id to the API `CommentID` here so the
    /// view controller stays free of that conversion. Rethrows the service error
    /// unchanged.
    func voteOnComment(serverCommentId: Int64, action: VoteStatus.Action) async throws {
        FunStats.record(.votesCast)
        try await lemmy.vote(
            serverCommentId: Lemmy.CommentID(serverCommentId),
            vote: action
        )
    }

    /// Saves or unsaves the comment `serverCommentId` for the backing account.
    /// Converts the local `Int64` id to the API `CommentID` here so the view
    /// controller stays free of that conversion. Rethrows the service error
    /// unchanged.
    func setSavedOnComment(serverCommentId: Int64, saved: Bool) async throws {
        try await lemmy.setSaved(
            serverCommentId: Lemmy.CommentID(serverCommentId),
            saved: saved
        )
    }
}
