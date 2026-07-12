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

    @ObservationIgnored
    private let fetchCommentsOperation: @MainActor (Lemmy.CommentSortType) async throws -> Void

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
        fetchCommentsOperation: (@MainActor (Lemmy.CommentSortType) async throws -> Void)? = nil
    ) {
        self.dependencies = dependencies
        self.appDatabase = appDatabase
        self.serverPostId = serverPostId
        self.accountScope = accountScope
        injectedLemmy = lemmy
        commentSortType = dependencies.preferencesService.defaultCommentSortType
        self.fetchCommentsOperation = fetchCommentsOperation ?? { sortType in
            try await accountScope.lemmyService
                .fetchComments(serverPostId: serverPostId, sortType: sortType)
        }
    }

    deinit {
        headerObservationTask?.cancel()
        commentObservationTask?.cancel()
        outboundObservationTask?.cancel()
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
    func refreshComments() async throws {
        try await fetchCommentsOperation(commentSortType)
    }

    /// Casts (or clears) a vote on the comment `serverCommentId` for the backing
    /// account. Converts the local `Int64` id to the API `CommentID` here so the
    /// view controller stays free of that conversion. Rethrows the service error
    /// unchanged.
    func voteOnComment(serverCommentId: Int64, action: VoteStatus.Action) async throws {
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
