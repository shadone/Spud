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

@MainActor
struct PostListViewModelLoadStateTests {
    private struct TestDependencies: HasAccountService, HasPreferencesService, HasReachabilityMonitor {
        let appDatabase: AppDatabase
        let accountService: AccountServiceType
        let preferencesService: PreferencesServiceType
        let reachabilityMonitor: ReachabilityMonitoring

        init(reachabilityMonitor: ReachabilityMonitoring) {
            let appDatabase = try! AppDatabase.inMemory()
            self.appDatabase = appDatabase
            accountService = AccountService(appDatabase: appDatabase)
            preferencesService = PreferencesService()
            self.reachabilityMonitor = reachabilityMonitor
        }
    }

    private func makeViewModel(
        reachabilityMonitor: ReachabilityMonitoring = StaticReachabilityMonitor(isOnline: true),
        slowThreshold: Duration = .milliseconds(20),
        hardCapTimeout: Duration = .seconds(5),
        feedKey: String = "feed-1",
        fetchFeedOperation: @escaping @MainActor (FeedHandle, String?) async throws -> String?
    ) -> PostListViewModel {
        let dependencies = TestDependencies(reachabilityMonitor: reachabilityMonitor)
        let feed = FeedHandle(
            feedKey: feedKey,
            feedType: .frontpage(listingType: .All, sortType: .Active)
        )
        return PostListViewModel(
            feed: feed,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: "kc-1"),
            appDatabase: dependencies.appDatabase,
            dependencies: dependencies,
            fetchFeedOperation: fetchFeedOperation,
            slowThreshold: slowThreshold,
            hardCapTimeout: hardCapTimeout
        )
    }

    @Test
    func successLeavesLoadingUntilSnapshotResolves() async {
        // A slow-hint threshold far longer than any scheduling latency, so the
        // default 20ms timer can't flip the state to slow: true during the brief
        // load window when this runs under heavy parallel test execution. This
        // test asserts the not-slow state; the slow hint has its own test.
        let vm = makeViewModel(slowThreshold: .seconds(30)) { _, _ in "next-cursor" }
        await vm.loadFirstPage()
        // Fetch succeeded but rows arrive via GRDB; still loading until snapshot.
        #expect(vm.loadState == .loading(slow: false))
        vm.resolveInitialSnapshot(rowCount: 3)
        #expect(vm.loadState == .loaded)
    }

    @Test
    func successWithZeroRowsResolvesEmpty() async {
        let vm = makeViewModel { _, _ in nil }
        await vm.loadFirstPage()
        vm.resolveInitialSnapshot(rowCount: 0)
        #expect(vm.loadState == .empty)
    }

    /// Regression: when the first observed snapshot is empty (it arrives before
    /// the tracked fetch persists posts) and the posts show up in a later
    /// snapshot, resolving on that later snapshot must settle the load. The view
    /// controller now calls `resolveInitialSnapshot` on every snapshot for
    /// exactly this reason - gating it to the first snapshot left `loadState`
    /// stuck at `.loading` forever on feeds whose first snapshot is empty (e.g.
    /// the Saved feed), so the skeleton and the pull-to-refresh spinner never
    /// cleared.
    @Test
    func laterNonEmptySnapshotResolvesLoadedAfterEmptyFirstSnapshot() {
        let vm = makeViewModel { _, _ in nil }
        // First (empty) snapshot, before any fetch has completed: stays loading.
        vm.resolveInitialSnapshot(rowCount: 0)
        #expect(vm.loadState == .loading(slow: false))
        // Posts arrive in a later snapshot: the load must now settle.
        vm.resolveInitialSnapshot(rowCount: 4)
        #expect(vm.loadState == .loaded)
    }

    @Test
    func thrownURLErrorBecomesFailedUnreachable() async {
        let vm = makeViewModel { _, _ in throw URLError(.timedOut) }
        await vm.loadFirstPage()
        #expect(vm.loadState == .failed(LoadFailure(kind: .unreachable, diagnostics: vm.lastFailureDiagnostics ?? "")))
    }

    @Test
    func offlineMonitorClassifiesFailureAsOffline() async {
        let monitor = StaticReachabilityMonitor(isOnline: false)
        let vm = makeViewModel(reachabilityMonitor: monitor) { _, _ in throw URLError(.timedOut) }
        await vm.loadFirstPage()
        guard case let .failed(failure) = vm.loadState else { Issue.record("expected failed")
            return
        }
        #expect(failure.kind == .offline)
    }

    @Test
    func hardCapTimesOutToUnreachable() async {
        let vm = makeViewModel(hardCapTimeout: .milliseconds(50)) { _, _ in
            try await Task.sleep(for: .seconds(10))
            return nil
        }
        await vm.loadFirstPage()
        guard case let .failed(failure) = vm.loadState else { Issue.record("expected failed")
            return
        }
        #expect(failure.kind == .unreachable)
    }

    @Test
    func slowHintFiresWhileStillLoading() async {
        var release: CheckedContinuation<String?, Error>?
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let vm = makeViewModel { _, _ in
            startedContinuation.yield(())
            return try await withCheckedThrowingContinuation { release = $0 }
        }
        let task = Task { await vm.loadFirstPage() }
        for await _ in started {
            break
        } // wait until the fetch has started

        // Wait past the 20ms slow threshold.
        try? await Task.sleep(for: .milliseconds(60))
        #expect(vm.loadState == .loading(slow: true))

        release?.resume(returning: nil)
        await task.value
    }

    @Test
    func paginationFailsThenRetrySucceeds() async {
        var callCount = 0
        let vm = makeViewModel { _, _ in
            callCount += 1
            if callCount == 2 { throw URLError(.timedOut) }
            return "next"
        }
        await vm.loadFirstPage() // call 1: succeeds
        vm.resolveInitialSnapshot(rowCount: 2)
        #expect(vm.loadState == .loaded)

        await vm.loadMore() // call 2: throws
        #expect(vm.paginationState == .failed)

        await vm.retryPagination() // call 3: succeeds
        #expect(vm.paginationState == .idle)
    }

    @Test
    func prepareForReloadResetsFailedToLoading() async {
        let vm = makeViewModel { _, _ in throw URLError(.timedOut) }
        await vm.loadFirstPage()
        guard case .failed = vm.loadState else { Issue.record("expected failed")
            return
        }
        vm.prepareForReload()
        #expect(vm.loadState == .loading(slow: false))
        #expect(vm.paginationState == .idle)
    }

    @Test
    func failInitialLoadMarksFailedUnreachable() {
        let vm = makeViewModel { _, _ in nil }
        vm.failInitialLoad()
        guard case let .failed(failure) = vm.loadState else { Issue.record("expected failed")
            return
        }
        #expect(failure.kind == .unreachable)
        #expect(vm.lastFailureDiagnostics != nil)
    }

    @Test
    func internalInconsistencyBecomesFailedUnreachable() async {
        let vm = makeViewModel { _, _ in throw LemmyServiceError.internalInconsistency(description: "") }
        await vm.loadFirstPage()
        guard case let .failed(failure) = vm.loadState else { Issue.record("expected failed")
            return
        }
        #expect(failure.kind == .unreachable)
    }

    /// Regression: switching the feed in place (the feed switcher reuses this
    /// view model via `showFeed`) mints a fresh UUID feedKey. The fetch must
    /// follow `self.feed` to the new key; if it keeps fetching the feed captured
    /// at init, the page is persisted under the stale key and the observed feed
    /// stays empty - the "all feeds show empty" bug.
    @Test
    func fetchTargetsCurrentFeedAfterSwitch() async {
        var fetchedFeedKeys: [String] = []
        let vm = makeViewModel { feed, _ in
            fetchedFeedKeys.append(feed.feedKey)
            return nil
        }

        await vm.loadFirstPage()
        #expect(fetchedFeedKeys == ["feed-1"])

        vm.switchFeed(to: .saved(sortType: .Active))
        await vm.loadFirstPage()

        #expect(fetchedFeedKeys.count == 2)
        #expect(fetchedFeedKeys[1] == vm.feed.feedKey, "fetch after switch must target the new feed")
        #expect(fetchedFeedKeys[1] != "feed-1", "fetch must not reuse the feed captured at init")
    }
}
