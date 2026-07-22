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
    /// `completions` in order (one per `fetchComments()` call), so a test can
    /// drive a sequence of fetches without a real network/DB round trip.
    private func makeViewModel(completions: [CommentFetchCompletion]) -> PostDetailViewModel {
        let dependencies = TestDependencies()
        var remaining = completions
        return PostDetailViewModel(
            serverPostId: 1,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: "kc-1"),
            appDatabase: dependencies.appDatabase,
            dependencies: dependencies,
            fetchCommentsOperation: { _ in
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
}
