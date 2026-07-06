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
    let serverPostId: Components.Schemas.PostID

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
    var headerRow: PostDetailHeaderRow?

    private(set) var commentSortType: Components.Schemas.CommentSortType

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

    /// Element ids of comments whose subtrees are currently collapsed. Pure
    /// view-layer state — no API or database involvement.
    @ObservationIgnored
    private(set) var collapsedElementIds: Set<Int64> = []

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

    @ObservationIgnored
    private let fetchCommentsOperation: @MainActor (Components.Schemas.CommentSortType) async throws -> Void

    @ObservationIgnored
    private var fetchTask: Task<Void, Never>?

    /// The resolved local `post` row id for the backing account, set during
    /// ``startObservations()`` bring-up. nil until resolved (and when the post
    /// is not yet mirrored). Read by the view controller to start the comment
    /// observation against the same row.
    @ObservationIgnored
    private(set) var postRowId: Int64?

    /// The live GRDB header observation feeding ``headerRow``. Owned here so it
    /// dies with the view model (see ``stopObservations()`` / `deinit`).
    @ObservationIgnored
    private var headerObservationTask: Task<Void, Never>?

    /// The live GRDB comment-tree observation feeding ``orderedComments`` +
    /// ``commentsRevision``. Owned here (like the header task) so it dies with
    /// the view model; restarted on a sort change (see
    /// ``restartComments(sortType:)``).
    @ObservationIgnored
    private var commentObservationTask: Task<Void, Never>?

    private var alertService: AlertServiceType {
        dependencies.alertService
    }

    private var reachabilityMonitor: ReachabilityMonitoring {
        dependencies.reachabilityMonitor
    }

    init(
        serverPostId: Components.Schemas.PostID,
        accountScope: AccountScope,
        appDatabase: AppDatabase,
        dependencies: Dependencies,
        fetchCommentsOperation: (@MainActor (Components.Schemas.CommentSortType) async throws -> Void)? = nil
    ) {
        self.dependencies = dependencies
        self.appDatabase = appDatabase
        self.serverPostId = serverPostId
        self.accountScope = accountScope
        commentSortType = dependencies.preferencesService.defaultCommentSortType
        self.fetchCommentsOperation = fetchCommentsOperation ?? { sortType in
            try await accountScope.lemmyService
                .fetchComments(serverPostId: serverPostId, sortType: sortType)
        }
    }

    deinit {
        headerObservationTask?.cancel()
        commentObservationTask?.cancel()
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
    func restartComments(sortType: Components.Schemas.CommentSortType) {
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
            try? await appDatabase.recordPostOpened(
                accountKeychainId: keychainId,
                serverPostId: serverPostId,
                commentCount: snapshotAndCount?.commentCount,
                snapshot: snapshotAndCount?.snapshot
            )
        }
    }

    func setCommentSortType(_ sortType: Components.Schemas.CommentSortType) {
        commentSortType = sortType
    }

    // MARK: - Collapse state (view-layer)

    /// Stores the latest ordered comment tree. Drops any collapsed ids that no
    /// longer exist in the new tree so stale state can't accumulate.
    func updateOrderedComments(_ rows: [PostDetailCommentRow]) {
        orderedComments = rows
        let existingIds = Set(rows.map(\.id))
        collapsedElementIds.formIntersection(existingIds)
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

    func fetchComments() async {
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
                try await fetchCommentsOperation(sortType)
                if !Task.isCancelled {
                    // A successful (winning) load clears any lingering failure so
                    // the empty / comments state can show.
                    commentFetchError = nil
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
}
