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

    // MARK: - A later-page failure must be reported, exactly once, without touching the inline failed state

    /// A later-page failure is reported exactly once, so a re-render cannot
    /// re-toast it.
    @Test
    func partialFailureIsConsumedOnce() async {
        let vm = makeViewModel(completion: .partial(.pageFetchFailed))
        await vm.fetchComments()
        #expect(vm.consumePartialCommentLoadFailure())
        #expect(!vm.consumePartialCommentLoadFailure())
    }

    /// A complete fetch reports nothing.
    @Test
    func completeFetchHasNoPartialFailureToConsume() async {
        let vm = makeViewModel(completion: .complete)
        await vm.fetchComments()
        #expect(!vm.consumePartialCommentLoadFailure())
    }

    /// A mid-pagination failure must NOT drive the inline failed state -- the
    /// pages that arrived stay on screen.
    @Test
    func partialFailureLeavesNoInlineFetchError() async {
        let vm = makeViewModel(completion: .partial(.pageFetchFailed))
        await vm.fetchComments()
        #expect(vm.commentFetchError == nil)
    }

    /// Exhausting the page budget is a resumable cursor, not a shortfall --
    /// it must not set the one-shot toast flag (that is what
    /// ``hasOutstandingCommentPages`` / the "Load more comments" row is for).
    @Test
    func pageBudgetExhaustedHasNoPartialFailureToConsume() async {
        let vm = makeViewModel(completion: .partial(.pageBudgetExhausted))
        await vm.fetchComments()
        #expect(!vm.consumePartialCommentLoadFailure())
    }

    /// Pull-to-refresh (``PostDetailViewModel/refreshComments()``) reuses the
    /// closure seam directly rather than the ``fetchComments()`` state
    /// machine, so it needs its own coverage: a later-page failure there must
    /// also be reported exactly once.
    @Test
    func refreshPartialFailureIsConsumedOnce() async throws {
        let vm = makeViewModel(completion: .partial(.pageFetchFailed))
        try await vm.refreshComments()
        #expect(vm.consumePartialCommentLoadFailure())
        #expect(!vm.consumePartialCommentLoadFailure())
    }

    /// A complete refresh reports nothing.
    @Test
    func refreshCompleteFetchHasNoPartialFailureToConsume() async throws {
        let vm = makeViewModel(completion: .complete)
        try await vm.refreshComments()
        #expect(!vm.consumePartialCommentLoadFailure())
    }

    /// A refreshed later-page failure must not be conflated with the resumable
    /// "Load more comments" cursor -- the two flags are independent even
    /// through the refresh path.
    @Test
    func refreshWithPageFetchFailedDoesNotMarkOutstandingPages() async throws {
        let vm = makeViewModel(completion: .partial(.pageFetchFailed))
        try await vm.refreshComments()
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

    // MARK: - Refresh must reflect the completion it gets back

    /// Pull-to-refresh reuses the `fetchCommentsOperation` seam directly (not
    /// the ``PostDetailViewModel/fetchComments()`` state machine), so it must
    /// capture the completion it gets back and update
    /// ``PostDetailViewModel/hasOutstandingCommentPages`` from it just like the
    /// winning branch of `fetchComments(maxPages:)` does. A refresh whose walk
    /// actually completes the tree must clear a flag left over from before the
    /// refresh -- otherwise the "Load more comments" row lingers with nothing
    /// left to load.
    @Test
    func refreshWithCompleteCompletionClearsOutstandingPages() async throws {
        let vm = makeViewModel(completions: [
            .partial(.pageBudgetExhausted),
            .complete,
        ])
        await vm.fetchComments()
        #expect(vm.hasOutstandingCommentPages)

        try await vm.refreshComments()

        #expect(!vm.hasOutstandingCommentPages)
    }

    /// The mirror direction: a refresh whose walk is genuinely partial must set
    /// the flag so the "Load more comments" row appears, even when nothing was
    /// outstanding before the refresh.
    @Test
    func refreshWithPartialCompletionSetsOutstandingPages() async throws {
        let vm = makeViewModel(completion: .partial(.pageBudgetExhausted))
        #expect(!vm.hasOutstandingCommentPages)

        try await vm.refreshComments()

        #expect(vm.hasOutstandingCommentPages)
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
