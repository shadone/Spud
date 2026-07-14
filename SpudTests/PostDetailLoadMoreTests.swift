//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import Testing
@testable import Spud

/// Covers `PostDetailViewModel`'s "load more replies" seam: the injectable
/// `fetchMoreCommentsOperation` forwards the right `(parentServerId, sortType)`
/// and rethrows on failure, and the per-row `loadingMoreElementIds` tracking
/// (`markLoadingMore` / `clearLoadingMore` / `isLoadingMore`) behaves.
@MainActor
struct PostDetailLoadMoreTests {
    private struct TestDependencies:
        HasAccountService, HasAlertService, HasPreferencesService, HasReachabilityMonitor
    {
        let appDatabase: AppDatabase
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let preferencesService: PreferencesServiceType
        let reachabilityMonitor: ReachabilityMonitoring

        init() {
            let appDatabase = try! AppDatabase.inMemory()
            self.appDatabase = appDatabase
            accountService = AccountService(appDatabase: appDatabase)
            alertService = AlertService()
            preferencesService = PreferencesService()
            reachabilityMonitor = StaticReachabilityMonitor(isOnline: true)
        }
    }

    private func makeViewModel(
        fetchMoreCommentsOperation: @escaping @MainActor (Int64, Lemmy.CommentSortType) async throws -> Void
    ) -> PostDetailViewModel {
        let dependencies = TestDependencies()
        return PostDetailViewModel(
            serverPostId: 1,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: "kc-1"),
            appDatabase: dependencies.appDatabase,
            dependencies: dependencies,
            fetchMoreCommentsOperation: fetchMoreCommentsOperation
        )
    }

    /// Builds a minimal `PostDetailCommentRow` keyed by `id` (the element id). Mirrors the
    /// row-builder helper in `PostDetailViewModelExpandAncestorsTests` so tests that only need to
    /// drive `updateOrderedComments` directly (no async/DB) match house style.
    private func row(id: Int64, depth: Int64 = 1) -> PostDetailCommentRow {
        PostDetailCommentRow(
            id: id, position: id, depth: depth,
            serverCommentId: id, body: "b\(id)",
            originalCommentUrl: "https://example.test/comment/\(id)",
            score: 0, voteStatus: nil, isSaved: false, isRemoved: false,
            isDistinguished: false, isDeleted: false, isCreatorModerator: false,
            isCreatorAdmin: false, isCreatorBannedFromCommunity: false,
            isCreatorBlocked: false, isCreatorSiteBanned: false, isCreatorBot: false,
            isCreatorAccountDeleted: false, removedReason: nil,
            published: Date(timeIntervalSince1970: 1_000_000),
            creatorName: "u\(id)", creatorPersonId: id,
            creatorActorId: "https://example.test",
            moreChildCount: nil, moreParentId: nil, childCount: nil
        )
    }

    @Test
    func loadMoreReplies_forwardsParentAndSort_andClearsFlagOnFailure() async {
        struct Boom: Error { }
        var captured: (parent: Int64, sort: Lemmy.CommentSortType)?
        let viewModel = makeViewModel(
            fetchMoreCommentsOperation: { parent, sort in
                captured = (parent, sort)
                throw Boom()
            }
        )

        viewModel.markLoadingMore(elementId: 7)
        #expect(viewModel.isLoadingMore(elementId: 7) == true)

        await #expect(throws: Boom.self) {
            try await viewModel.loadMoreReplies(elementId: 7, parentServerId: 99)
        }
        #expect(captured?.parent == 99)
        #expect(captured?.sort == viewModel.commentSortType)
        // On failure the VC clears the flag; simulate the VC step and confirm it clears.
        viewModel.clearLoadingMore(elementId: 7)
        #expect(viewModel.isLoadingMore(elementId: 7) == false)
    }

    /// Covers the one behaviorally-novel line in `updateOrderedComments`:
    /// `loadingMoreElementIds.formIntersection(existingIds)`. A successful splice replaces the
    /// "load more" placeholder row with the loaded comments, so the placeholder's element id
    /// disappears from the new tree - this must auto-clear the loading flag with no explicit
    /// `clearLoadingMore` call, or the row would render a stuck spinner forever.
    @Test
    func updateOrderedComments_autoClearsLoadingFlagForSplicedAwayElement() {
        let viewModel = makeViewModel(fetchMoreCommentsOperation: { _, _ in })

        viewModel.updateOrderedComments([row(id: 1), row(id: 2)])
        viewModel.markLoadingMore(elementId: 2)
        #expect(viewModel.isLoadingMore(elementId: 2) == true)

        // Element 2 (the "load more" placeholder) is spliced away by the successful fetch.
        viewModel.updateOrderedComments([row(id: 1)])

        #expect(viewModel.isLoadingMore(elementId: 2) == false)
    }
}
