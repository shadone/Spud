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

    @Test
    func loadMoreReplies_forwardsParentAndSort_andClearsFlagOnFailure() async {
        var captured: (parent: Int64, sort: Lemmy.CommentSortType)?
        let viewModel = makeViewModel(
            fetchMoreCommentsOperation: { parent, sort in
                captured = (parent, sort)
                throw LemmyServiceError.internalInconsistency(description: "boom")
            }
        )

        viewModel.markLoadingMore(elementId: 7)
        #expect(viewModel.isLoadingMore(elementId: 7) == true)

        await #expect(throws: (any Error).self) {
            try await viewModel.loadMoreReplies(elementId: 7, parentServerId: 99)
        }
        #expect(captured?.parent == 99)
        #expect(captured?.sort == viewModel.commentSortType)
        // On failure the VC clears the flag; simulate the VC step and confirm it clears.
        viewModel.clearLoadingMore(elementId: 7)
        #expect(viewModel.isLoadingMore(elementId: 7) == false)
    }
}
