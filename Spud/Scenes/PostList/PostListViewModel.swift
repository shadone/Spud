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
import SpudUtilKit

private let logger = Logger.app

enum FeedLoadState: Equatable {
    /// Initial fetch in flight. `slow == true` after the escalation threshold.
    case loading(slow: Bool)
    /// At least one post is visible.
    case loaded
    /// The fetch succeeded but there are no posts.
    case empty
    /// The initial fetch failed.
    case failed(LoadFailure)
}

enum PaginationState: Equatable {
    case idle
    case loading
    case failed
}

@MainActor
@Observable
final class PostListViewModel {
    typealias OwnDependencies = HasAccountService & HasPreferencesService & HasReachabilityMonitor
    typealias Dependencies = OwnDependencies

    @ObservationIgnored
    private let dependencies: OwnDependencies

    @ObservationIgnored
    private let appDatabase: AppDatabase

    @ObservationIgnored
    let accountScope: AccountScope

    var feed: FeedHandle
    var accountKeychainId: String {
        accountScope.accountKeychainId
    }

    var navigationTitle: String

    private(set) var loadState: FeedLoadState = .loading(slow: false)
    private(set) var paginationState: PaginationState = .idle

    /// Diagnostics from the most recent failure, for the "Copy details" action.
    @ObservationIgnored
    private(set) var lastFailureDiagnostics: String?

    /// Fetches one page of the given feed and returns the next cursor. Takes the
    /// `FeedHandle` as a parameter (rather than capturing one) so callers always
    /// pass the view model's *current* `feed`: an in-place feed switch swaps
    /// `self.feed`, and the fetch must follow it to the new feedKey.
    @ObservationIgnored
    private let fetchFeedOperation: @MainActor (FeedHandle, String?) async throws -> String?
    @ObservationIgnored
    private let slowThreshold: Duration
    @ObservationIgnored
    private let hardCapTimeout: Duration

    @ObservationIgnored
    private var nextPageCursor: String?
    @ObservationIgnored
    private var feedExhausted = false
    @ObservationIgnored
    private var hasCompletedInitialFetch = false
    @ObservationIgnored
    private var slowHintTask: Task<Void, Never>?

    // MARK: - Row observation state

    /// The full ordered feed snapshot as last emitted by the GRDB row
    /// observation this view model owns (see ``startObservations()``). The view
    /// controller filters this down to the visible rows (hide-read) and renders.
    ///
    /// Deliberately `@ObservationIgnored`: the display-preference reactions read
    /// it on every hide-read toggle, and if reads of it invalidated observers
    /// each toggle would spuriously re-run the whole apply pipeline. Because it
    /// is invisible to observation, the published ``rowsRevision`` counter is the
    /// explicit signal that a fresh DB snapshot landed.
    @ObservationIgnored
    private(set) var orderedRows: [PostListRow] = []

    /// `serverPostId` -> row lookup for the current snapshot, rebuilt in the same
    /// synchronous turn as ``orderedRows`` inside ``updateRows(_:)``. The view
    /// controller resolves a tapped / shared / moderated post through
    /// ``row(forServerPostId:)`` instead of scanning ``orderedRows``. Kept on the
    /// view model (not the view controller) so it and ``orderedRows`` can never
    /// drift: an interleaved snapshot apply during a reaction suspension always
    /// sees a lookup consistent with the rows it renders.
    ///
    /// Deliberately `@ObservationIgnored` for the same reason as ``orderedRows``.
    @ObservationIgnored
    private var rowsByServerPostId: [Int64: PostListRow] = [:]

    /// Monotonic per-emit signal for the row observation. Bumped exactly once
    /// each time the GRDB feed snapshot is delivered — after ``updateRows(_:)``
    /// has stored the new rows. The view controller keys its row reaction
    /// pipeline (pinned-read seed, hide-read filter, snapshot apply,
    /// applyLoadState) on this, since ``orderedRows`` is `@ObservationIgnored`
    /// and cannot serve as an observation trigger. Starts at 0 (nothing emitted
    /// yet); the reaction loop ignores that initial value and acts only on the
    /// increments. Monotonic across feed switches (never reset), like
    /// PostDetail's `commentsRevision`.
    private(set) var rowsRevision: Int = 0

    /// The set of already-read server post ids captured from the FIRST snapshot
    /// of the current observation. The view controller seeds its `pinnedReadIds`
    /// hide-read session pin from this on its first reaction, so `onRefresh`
    /// hide-read only sweeps posts read BEFORE this feed view began (posts read
    /// while scrolling stay until the next refresh — the semantics of the former
    /// inline first-snapshot pin). Computed on the VM's exact first emit here —
    /// not re-derived from ``orderedRows`` in the coalescing view-controller
    /// reaction — so the pin always reflects the FIRST snapshot even when a later
    /// emit is the first the reaction observes. Reset on every restart.
    @ObservationIgnored
    private(set) var firstSnapshotReadIds: Set<Int64> = []

    /// The live GRDB row observation feeding ``orderedRows`` + ``rowsRevision``
    /// (PostDetail template). Owned here so it stops on an explicit
    /// ``stopObservations()`` / task cancel; restarted on a feed switch / reload
    /// (see ``restartObservations(keepingContent:)``). Each observation task
    /// binds a strong `self` for the whole `for await` loop, so the view model
    /// cannot deinit while one is still running; the `deinit` cancel is
    /// belt-and-braces cleanup for the already-stopped case.
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?

    /// The VM's first-emit latch for the current observation. Drives the
    /// first-snapshot ``firstSnapshotReadIds`` capture, ``resolveInitialSnapshot``,
    /// and the cached-empty ``loadFirstPage`` kick. Reset on every restart.
    @ObservationIgnored
    private var hasReceivedFirstSnapshot = false

    private var accountService: AccountServiceType {
        dependencies.accountService
    }

    private var reachabilityMonitor: ReachabilityMonitoring {
        dependencies.reachabilityMonitor
    }

    init(
        feed: FeedHandle,
        accountScope: AccountScope,
        appDatabase: AppDatabase,
        dependencies: Dependencies,
        fetchFeedOperation: (@MainActor (FeedHandle, String?) async throws -> String?)? = nil,
        slowThreshold: Duration = .seconds(8),
        hardCapTimeout: Duration = .seconds(25)
    ) {
        self.dependencies = dependencies
        self.appDatabase = appDatabase
        self.accountScope = accountScope
        self.feed = feed
        self.slowThreshold = slowThreshold
        self.hardCapTimeout = hardCapTimeout
        navigationTitle = Self.navigationTitle(for: feed.feedType)
        let scope = accountScope
        let preferencesService = dependencies.preferencesService
        self.fetchFeedOperation = fetchFeedOperation ?? { feedToFetch, cursor in
            // Read the CURRENT NSFW preference at fetch time so a changed
            // preference is honoured on the next page / reload (the filtering
            // is server-side via the request param, so it applies to
            // signed-out accounts too).
            let showNsfw = preferencesService.showNsfw
            return try await scope.lemmyService.fetchFeed(
                feedToFetch,
                pageCursor: cursor,
                showNsfw: showNsfw
            )
        }
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Feed switching (reset state)

    func didChangeSortType(_ sortType: Components.Schemas.SortType) {
        let newFeed = accountService.createFeed(duplicateOf: feed, forAccountKeychainId: accountKeychainId, sortType: sortType)
        resetForNewFeed(newFeed)
    }

    func didClickReload() {
        // The Downloaded feed has no network feed to reload; a pull-to-refresh
        // just re-observes the local rows (the view controller's `feedChanged`
        // restarts the observation). Minting a fresh feed here would do nothing
        // useful, so no-op — keeping the reload path network-free.
        guard !isDownloadedFeed else { return }
        let newFeed = accountService.createFeed(duplicateOf: feed, forAccountKeychainId: accountKeychainId)
        resetForNewFeed(newFeed)
    }

    func switchFeed(to feedType: FeedType) {
        let newFeed = accountService.createFeed(forAccountKeychainId: accountKeychainId, feedType: feedType)
        resetForNewFeed(newFeed)
    }

    private func resetForNewFeed(_ newFeed: FeedHandle) {
        feed = newFeed
        nextPageCursor = nil
        feedExhausted = false
        hasCompletedInitialFetch = false
        loadState = .loading(slow: false)
        paginationState = .idle
        navigationTitle = Self.navigationTitle(for: newFeed.feedType)
    }

    // MARK: - Initial load

    /// Reset the initial-load state so a reload of the SAME feed starts from
    /// `.loading` rather than re-pinning a stale `.failed` surface (the retry
    /// and reconnect paths re-run `feedChanged()` without minting a new feed).
    func prepareForReload() {
        loadState = .loading(slow: false)
        paginationState = .idle
        hasCompletedInitialFetch = false
    }

    /// Fetch the first page with the hard-cap timeout and slow-hint escalation.
    /// Leaves `loadState` at `.loading` on success — the GRDB first snapshot
    /// resolves `.loaded` / `.empty` via `resolveInitialSnapshot(rowCount:)`.
    func loadFirstPage() async {
        // The Downloaded feed is local-only: its observation owns the load state
        // and there is no page to fetch. No-op so no network request is ever
        // issued (belt-and-braces alongside `fetchFeed` returning nil).
        guard !isDownloadedFeed else { return }
        loadState = .loading(slow: false)
        startSlowHint()
        defer { cancelSlowHint() }
        do {
            let next = try await withTimeout(hardCapTimeout) { [self] in
                try await fetchFeedOperation(feed, nextPageCursor)
            }
            nextPageCursor = next
            if next == nil { feedExhausted = true }
            hasCompletedInitialFetch = true
        } catch {
            let failure = LoadFailure.classify(error, isOnline: reachabilityMonitor.isOnline)
            lastFailureDiagnostics = failure.diagnostics
            loadState = .failed(failure)
        }
    }

    /// Resolve the initial load once GRDB delivers the first snapshot. No-op if
    /// we've already left the loading state (failed/loaded/empty).
    func resolveInitialSnapshot(rowCount: Int) {
        guard case .loading = loadState else { return }
        if rowCount > 0 {
            loadState = .loaded
        } else if hasCompletedInitialFetch {
            loadState = .empty
        }
        // rowCount == 0 and no fetch yet: a cached-but-empty feed. The controller
        // kicks loadFirstPage(); we stay in .loading until it resolves.
    }

    /// Dismisses the current failure and shows the empty state for this feed.
    /// Backs the error state's "Work offline" action.
    func dismissToEmpty() {
        loadState = .empty
    }

    /// Marks the initial load as failed when the feed row never materialized
    /// after a fetch that reported success - i.e. persistence silently failed.
    /// Surfaces a retryable `.unreachable` failure so the post list shows the
    /// error surface instead of an orphaned spinner or skeleton.
    func failInitialLoad() {
        let failure = LoadFailure(kind: .unreachable, diagnostics: "Feed page did not persist")
        lastFailureDiagnostics = failure.diagnostics
        loadState = .failed(failure)
    }

    private func startSlowHint() {
        slowHintTask?.cancel()
        slowHintTask = Task { [weak self, slowThreshold] in
            try? await Task.sleep(for: slowThreshold)
            guard let self, !Task.isCancelled else { return }
            if case .loading = loadState {
                loadState = .loading(slow: true)
            }
        }
    }

    private func cancelSlowHint() {
        slowHintTask?.cancel()
        slowHintTask = nil
    }

    // MARK: - Row observation

    /// Whether the current feed is the local-only Downloaded feed. It reads
    /// exclusively from GRDB (`post.downloadedAt`) and must never touch the
    /// network — the observation, load, and pagination paths all branch on this.
    private var isDownloadedFeed: Bool {
        if case .downloaded = feed.feedType { return true }
        return false
    }

    /// Starts the row observation as one bring-up task: resolve the feed's local
    /// row id, lazily fetching the first page when the feed hasn't materialized
    /// yet (the importer creates the feed row on the first fetch), then observe
    /// the ordered feed rows. Per emit, IN ORDER (matching the pre-move inline
    /// loop verbatim): latch the first snapshot, capture its
    /// ``firstSnapshotReadIds`` pin, resolve the top-level load state on EVERY
    /// emit BEFORE the view controller applies (the Saved-feed stuck-skeleton
    /// guard), store the rows + rebuild the lookup atomically, bump
    /// ``rowsRevision`` so the view controller reacts, then kick the tracked
    /// fetch when the first snapshot is a cached-but-empty feed. Cancels any
    /// prior observation first, so it is safe to call on a feed switch / reload.
    func startObservations() {
        stopObservations()
        hasReceivedFirstSnapshot = false
        firstSnapshotReadIds = []

        if isDownloadedFeed {
            startDownloadedObservations()
            return
        }

        let feedKey = feed.feedKey
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Feeds are created lazily by the importer on the first fetch. If the
            // row doesn't exist yet, await the tracked first page so the importer
            // creates it before we set up the observation.
            if appDatabase.feedRowIdSync(forFeedKey: feedKey) == nil {
                await loadFirstPage()
                if Task.isCancelled { return }
            }

            guard let feedRowId = appDatabase.feedRowIdSync(forFeedKey: feedKey) else {
                if case .failed = loadState {
                    // loadFirstPage already surfaced the failure; the loadState
                    // observation ends the refresh control and renders the error
                    // surface.
                } else {
                    // Defensive: the row is missing but loadFirstPage did not
                    // report a failure. Never leave a pull-to-refresh spinner or
                    // the skeleton orphaned — reach a terminal state. Setting
                    // `.failed` drives the view controller's loadState reaction,
                    // which ends the refresh control and hides the skeleton (the
                    // UI teardown the pre-move inline path did explicitly).
                    failInitialLoad()
                }
                return
            }

            for await rows in appDatabase.observePostListRows(feedId: feedRowId) {
                if Task.isCancelled { break }
                let isFirstSnapshot = !hasReceivedFirstSnapshot
                hasReceivedFirstSnapshot = true
                if isFirstSnapshot {
                    // Pin the rows already read when this feed view began, so
                    // `onRefresh` hide-read only hides those (posts read while
                    // scrolling stay until the next refresh). Captured on the
                    // exact first emit here — not re-derived from `orderedRows`
                    // in the coalescing view-controller reaction — so the pin
                    // always reflects the FIRST snapshot.
                    firstSnapshotReadIds = HideReadPostsFilter.readIds(in: rows)
                }
                // Resolve the top-level load state on EVERY snapshot, and BEFORE
                // the view controller applies. Gating resolution to the first
                // snapshot leaves loadState stuck at `.loading` forever when a
                // feed's first snapshot is empty and its posts arrive in a later
                // one — the skeleton and the pull-to-refresh spinner then never
                // clear. resolveInitialSnapshot self-guards once settled.
                resolveInitialSnapshot(rowCount: rows.count)

                updateRows(rows)
                rowsRevision += 1

                if isFirstSnapshot, case .loading = loadState, rows.isEmpty {
                    // Cached-but-empty feed: kick the tracked initial fetch.
                    await loadFirstPage()
                }
            }
        }
    }

    /// Observes the Downloaded (offline) feed straight from the durable
    /// `post.downloadedAt` marker, bypassing the feed-row / network bring-up that
    /// `startObservations()` uses for every other feed. There is no feed row to
    /// resolve and NO fetch: the local DB is the complete, authoritative state.
    ///
    /// Because there is nothing to fetch, mark the (nonexistent) initial fetch
    /// complete and the feed exhausted up front — that lets
    /// `resolveInitialSnapshot` settle an empty snapshot to `.empty` (instead of
    /// leaving the skeleton spinning forever, since no `loadFirstPage` will ever
    /// flip `hasCompletedInitialFetch`), and it makes `loadMore` a no-op. Opening
    /// this feed offline shows the downloaded posts immediately — never a spinner
    /// or an error surface.
    private func startDownloadedObservations() {
        hasCompletedInitialFetch = true
        feedExhausted = true
        let keychainId = accountKeychainId
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await rows in appDatabase.observeDownloadedPostListRows(forAccountKeychainId: keychainId) {
                if Task.isCancelled { break }
                let isFirstSnapshot = !hasReceivedFirstSnapshot
                hasReceivedFirstSnapshot = true
                if isFirstSnapshot {
                    firstSnapshotReadIds = HideReadPostsFilter.readIds(in: rows)
                }
                // Resolve the load state on EVERY snapshot (mirrors the feed-row
                // path): a downloaded post hidden/unhidden can flip loaded <->
                // empty, and the first snapshot may arrive empty then populate.
                resolveInitialSnapshot(rowCount: rows.count)
                updateRows(rows)
                rowsRevision += 1
            }
        }
    }

    /// Cancels the row observation. Called on restart and from `deinit`.
    func stopObservations() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// Restarts the row observation for the current feed. A pull-to-refresh (and
    /// an in-place feed switch that keeps content) leaves the existing rows +
    /// lookup in place until the new observation's first emit swaps them in — the
    /// refresh control is the only progress indicator. A non-keeping restart
    /// (feed switch, reload) clears them so nothing stale renders; the view
    /// controller clears its diffable snapshot in lockstep (the two must reset
    /// together, or a cell re-dequeued before the new first snapshot resolves to
    /// no row — "Missing PostListRow"). Either way ``startObservations()`` resets
    /// the first-snapshot latch + pin so the next emit re-seeds them.
    func restartObservations(keepingContent: Bool) {
        if !keepingContent {
            orderedRows = []
            rowsByServerPostId = [:]
        }
        startObservations()
    }

    /// The loaded feed row for `serverPostId`, or nil when it isn't in the
    /// current snapshot. Backs every view-controller action that needs a row
    /// (share, moderate, visit community / author, mute, seen, save-state).
    func row(forServerPostId serverPostId: Int64) -> PostListRow? {
        rowsByServerPostId[serverPostId]
    }

    /// Stores the latest ordered feed snapshot, rebuilding ``rowsByServerPostId``
    /// in the same synchronous turn so the lookup and ``orderedRows`` are always
    /// mutually consistent (never observable in a state where one reflects a
    /// newer snapshot than the other). Does NOT bump ``rowsRevision`` — the
    /// observation loop bumps it once, immediately after this returns.
    private func updateRows(_ rows: [PostListRow]) {
        orderedRows = rows
        rowsByServerPostId = Dictionary(uniqueKeysWithValues: rows.map { ($0.serverPostId, $0) })
    }

    // MARK: - Pagination

    func didScrollToBottom() {
        Task { await loadMore() }
    }

    func loadMore() async {
        // The Downloaded feed never paginates (there is no next page). No-op so
        // scrolling to the bottom can't spin a pagination request.
        guard !isDownloadedFeed else { return }
        guard loadState == .loaded, paginationState != .loading, !feedExhausted else { return }
        paginationState = .loading
        await performPagination()
    }

    func retryPagination() async {
        guard paginationState == .failed else { return }
        paginationState = .loading
        await performPagination()
    }

    private func performPagination() async {
        do {
            let next = try await withTimeout(hardCapTimeout) { [self] in
                try await fetchFeedOperation(feed, nextPageCursor)
            }
            nextPageCursor = next
            if next == nil { feedExhausted = true }
            paginationState = .idle
        } catch {
            let failure = LoadFailure.classify(error, isOnline: reachabilityMonitor.isOnline)
            lastFailureDiagnostics = failure.diagnostics
            logger.error("Pagination fetch failed: \(failure.diagnostics, privacy: .public)")
            paginationState = .failed
        }
    }

    // MARK: - Host / empty / title (unchanged behavior)

    var instanceHost: String? {
        switch feed.feedType {
        case let .community(_, instance, _):
            return instance.host
        case .frontpage, .saved, .downloaded:
            return accountScope.instanceActorId?.host
        }
    }

    struct EmptyState {
        let symbolName: String
        let title: String
        let message: String
    }

    var emptyState: EmptyState {
        switch feed.feedType {
        case .saved:
            return EmptyState(
                symbolName: "bookmark",
                title: NSLocalizedString("No saved posts yet", comment: "Empty-state title for the saved-posts feed"),
                message: NSLocalizedString("Posts you save will show up here.", comment: "Empty-state message for the saved-posts feed")
            )
        case .downloaded:
            return EmptyState(
                symbolName: "arrow.down.circle",
                title: NSLocalizedString("No downloaded posts yet", comment: "Empty-state title for the downloaded-posts feed"),
                message: NSLocalizedString("Posts you download for offline reading will show up here.", comment: "Empty-state message for the downloaded-posts feed")
            )
        case .frontpage, .community:
            return EmptyState(
                symbolName: "tray",
                title: NSLocalizedString("No posts", comment: "Empty-state title for a post feed"),
                message: NSLocalizedString("There are no posts to show here.", comment: "Empty-state message for a post feed")
            )
        }
    }

    private static func navigationTitle(for feedType: FeedType) -> String {
        switch feedType {
        case let .frontpage(listingType, _):
            switch listingType {
            case .All: return "All"
            case .Local: return "Local"
            case .Subscribed: return "Subscribed"
            case .ModeratorView: return "Moderator view"
            }
        case let .community(communityName, instance, _):
            return "\(communityName)@\(instance.hostWithPort)"
        case .saved:
            return NSLocalizedString("Saved", comment: "Navigation title for the saved-posts feed")
        case .downloaded:
            return NSLocalizedString("Downloaded", comment: "Navigation title for the downloaded (offline) posts feed")
        }
    }

    // MARK: - Data accessors (view controller + its action seams)

    /// The backing account's home-instance actor id (its `ap_id` host), or nil
    /// when signed out / unresolved. Used to build a post's canonical share URL
    /// when the row carries no `ap_id` permalink of its own. A synchronous DB
    /// read, matching the pre-move call shape at the share site.
    var instanceActorId: String? {
        appDatabase.accountInstanceActorIdSync(forKeychainId: accountKeychainId)
    }

    /// The backing account's `(accountId, siteId)` local row ids, or nil when
    /// the account hasn't been imported yet. Backs the offline-download launch
    /// path's "is this feed importable" guard and run seeding. A synchronous DB
    /// read.
    func accountAndSiteRowIds() -> (accountId: Int64, siteId: Int64)? {
        appDatabase.accountAndSiteRowIdSync(forKeychainId: accountKeychainId)
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

    /// Persists a "seen" interaction for `serverPostId` on the backing account
    /// from the given render snapshot. Fire-and-forget by convention: the caller
    /// wraps it in a detached task and ignores the result. Failures are
    /// non-fatal (the `try?` mirrors the pre-move write); the view controller
    /// keeps the dwell tracker / timer and only the write moved here.
    func recordSeen(serverPostId: Int64, snapshot: PostInteractionSnapshot) async {
        try? await appDatabase.recordPostSeen(
            accountKeychainId: accountKeychainId,
            serverPostId: serverPostId,
            snapshot: snapshot
        )
    }
}
