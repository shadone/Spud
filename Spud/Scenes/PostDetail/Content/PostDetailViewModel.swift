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
        HasPreferencesService
    typealias Dependencies = OwnDependencies

    @ObservationIgnored
    private let dependencies: OwnDependencies

    @ObservationIgnored
    let serverPostId: Components.Schemas.PostID

    @ObservationIgnored
    let accountScope: AccountScope

    var accountKeychainId: String {
        accountScope.accountKeychainId
    }

    var commentSortType: Components.Schemas.CommentSortType

    /// True while a (non-pull-refresh) comment fetch is in flight. Pull-to-refresh
    /// calls `LemmyService.fetchComments` directly and does not flip this.
    private(set) var isLoadingComments: Bool = false

    /// The full, ordered comment tree as last emitted by the GRDB observation.
    /// Collapse is computed against this; it is never mutated by collapse.
    @ObservationIgnored
    private(set) var orderedComments: [PostDetailCommentRow] = []

    /// Element ids of comments whose subtrees are currently collapsed. Pure
    /// view-layer state — no API or database involvement.
    @ObservationIgnored
    private(set) var collapsedElementIds: Set<Int64> = []

    /// The `lastOpenedAt` from before this visit, used to flag comments
    /// published since. nil on a first-ever visit (nothing is "new"). Set once
    /// by the view controller during observation bring-up.
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

    private var alertService: AlertServiceType {
        dependencies.alertService
    }

    init(
        serverPostId: Components.Schemas.PostID,
        accountScope: AccountScope,
        dependencies: Dependencies
    ) {
        self.dependencies = dependencies
        self.serverPostId = serverPostId
        self.accountScope = accountScope
        commentSortType = dependencies.preferencesService.defaultCommentSortType
    }

    func didChangeCommentSortType(_ sortType: Components.Schemas.CommentSortType) {
        commentSortType = sortType
        Task { await fetchComments() }
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
        // De-dup overlapping fetches: only one comment fetch runs at a time. A
        // second trigger while one is already in flight is a no-op — its result
        // would be redundant, and letting it run would reset `isLoadingComments`
        // early and flap the loading state. (When a per-post comment sort
        // switcher is added, this should become cancel-and-replace so a sort
        // change supersedes the in-flight fetch rather than being dropped.)
        guard !isLoadingComments else { return }
        isLoadingComments = true
        defer { isLoadingComments = false }
        do {
            try await accountScope.lemmyService
                .fetchComments(serverPostId: serverPostId, sortType: commentSortType)
        } catch {
            alertService.handle(error, for: .fetchComments)
        }
    }
}
