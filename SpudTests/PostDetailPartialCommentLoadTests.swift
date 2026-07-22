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

/// A comment fetch that stopped with pages outstanding must say so. The header
/// count cannot be used for this -- server counts and returned row counts
/// legitimately differ -- so the signal comes from the fetch's own completion.
@MainActor
struct PostDetailPartialCommentLoadTests {
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
            preferencesService = PreferencesService.ephemeral()
            reachabilityMonitor = StaticReachabilityMonitor(isOnline: true)
        }
    }

    /// Builds a view model whose `fetchCommentsOperation` returns each of
    /// `completions` in order (one per fetch call), so a test can drive a
    /// sequence of fetches without a real network/DB round trip. When
    /// `maxPagesCapture` is supplied, every call's requested `maxPages` bound
    /// is recorded on it in order — the seam for the page-budget-growth tests
    /// below.
    private func makeViewModel(
        completions: [CommentFetchCompletion],
        maxPagesCapture: MaxPagesCapture? = nil
    ) -> PostDetailViewModel {
        let dependencies = TestDependencies()
        var remaining = completions
        return PostDetailViewModel(
            serverPostId: 1,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: "kc-1"),
            appDatabase: dependencies.appDatabase,
            dependencies: dependencies,
            fetchCommentsOperation: { _, maxPages in
                maxPagesCapture?.record(maxPages)
                guard !remaining.isEmpty else { return .complete }
                return remaining.removeFirst()
            }
        )
    }

    private func makeViewModel(completion: CommentFetchCompletion) -> PostDetailViewModel {
        makeViewModel(completions: [completion])
    }

    @Test
    func exhaustedPageBudgetMarksOutstandingPages() async {
        let vm = makeViewModel(completion: .partial(.pageBudgetExhausted))
        await vm.fetchComments()
        #expect(vm.hasOutstandingCommentPages)
    }

    @Test
    func completeFetchMarksNoOutstandingPages() async {
        let vm = makeViewModel(completion: .complete)
        await vm.fetchComments()
        #expect(!vm.hasOutstandingCommentPages)
    }

    /// A later-page failure is a shortfall, not an outstanding page the reader
    /// can tap to resume -- it must not raise the "load more" affordance.
    @Test
    func pageFetchFailureDoesNotMarkOutstandingPages() async {
        let vm = makeViewModel(completion: .partial(.pageFetchFailed))
        await vm.fetchComments()
        #expect(!vm.hasOutstandingCommentPages)
    }

    /// A fresh fetch (sort change, retry) clears a stale outstanding-pages flag.
    @Test
    func aCompleteRefetchClearsOutstandingPages() async {
        let completions: [CommentFetchCompletion] = [
            .partial(.pageBudgetExhausted),
            .complete,
        ]
        let vm = makeViewModel(completions: completions)
        await vm.fetchComments()
        #expect(vm.hasOutstandingCommentPages)
        await vm.fetchComments()
        #expect(!vm.hasOutstandingCommentPages)
    }

    // MARK: - Page-budget growth (the "Load more comments" row must genuinely load more)

    /// Each tap on "Load more comments" must request a LARGER page bound than
    /// the last one -- otherwise `LemmyService.fetchComments` (which always
    /// restarts its walk at page 1, never resuming a persisted cursor) would
    /// re-walk the identical first N pages on every tap and the tree could
    /// never grow. This is the defect this whole file exists to catch.
    @Test
    func consecutiveLoadMoreTapsRequestIncreasingBounds() async {
        let capture = MaxPagesCapture()
        let vm = makeViewModel(
            completions: [
                .partial(.pageBudgetExhausted),
                .partial(.pageBudgetExhausted),
                .partial(.pageBudgetExhausted),
            ],
            maxPagesCapture: capture
        )

        await vm.fetchComments()
        await vm.loadMoreCommentPages()
        await vm.loadMoreCommentPages()

        #expect(capture.received == [
            LemmyService.maxCommentPages,
            LemmyService.maxCommentPages * 2,
            LemmyService.maxCommentPages * 3,
        ])
    }

    /// A fresh, non-continuation fetch (``PostDetailViewModel/fetchComments()``
    /// -- the initial load, a sort change, or a Retry) must go back to the
    /// base budget, not inherit whatever bound a prior "Load more comments"
    /// streak had grown to.
    @Test
    func freshFetchAfterLoadMoreResetsToBaseBudget() async {
        let capture = MaxPagesCapture()
        let vm = makeViewModel(
            completions: [
                .partial(.pageBudgetExhausted),
                .partial(.pageBudgetExhausted),
                .complete,
            ],
            maxPagesCapture: capture
        )

        await vm.fetchComments()
        await vm.loadMoreCommentPages()
        #expect(capture.received[1] > capture.received[0], "sanity: the tap must have grown the bound")

        await vm.fetchComments()

        #expect(capture.received[2] == LemmyService.maxCommentPages)
    }

    /// Pull-to-refresh (``PostDetailViewModel/refreshComments()``) bypasses the
    /// cancel-and-replace state machine and calls the closure seam directly,
    /// but it must reset to the base budget exactly like ``fetchComments()``
    /// does -- a refresh after a "Load more" streak must not silently re-walk
    /// an inflated number of pages.
    @Test
    func refreshResetsToBaseBudgetAfterLoadMore() async throws {
        let capture = MaxPagesCapture()
        let vm = makeViewModel(
            completions: [
                .partial(.pageBudgetExhausted),
                .partial(.pageBudgetExhausted),
                .complete,
            ],
            maxPagesCapture: capture
        )

        await vm.fetchComments()
        await vm.loadMoreCommentPages()

        try await vm.refreshComments()

        #expect(capture.received[2] == LemmyService.maxCommentPages)
    }
}

/// Records, in order, the `maxPages` bound each `fetchCommentsOperation` call
/// requested. `@MainActor` to match the closure's isolation.
@MainActor
private final class MaxPagesCapture {
    private(set) var received: [Int] = []

    func record(_ maxPages: Int) {
        received.append(maxPages)
    }
}
