//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import XCTest
@testable import Spud

@MainActor
final class PostListViewModelLoadStateTests: XCTestCase {
    private struct TestDependencies: HasAccountService, HasReachabilityMonitor {
        let accountService: AccountServiceType
        let reachabilityMonitor: ReachabilityMonitoring

        init(reachabilityMonitor: ReachabilityMonitoring) {
            accountService = AccountService(appDatabase: try! AppDatabase.inMemory())
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
            dependencies: dependencies,
            fetchFeedOperation: fetchFeedOperation,
            slowThreshold: slowThreshold,
            hardCapTimeout: hardCapTimeout
        )
    }

    func testSuccessLeavesLoadingUntilSnapshotResolves() async {
        let vm = makeViewModel { _, _ in "next-cursor" }
        await vm.loadFirstPage()
        // Fetch succeeded but rows arrive via GRDB; still loading until snapshot.
        XCTAssertEqual(vm.loadState, .loading(slow: false))
        vm.resolveInitialSnapshot(rowCount: 3)
        XCTAssertEqual(vm.loadState, .loaded)
    }

    func testSuccessWithZeroRowsResolvesEmpty() async {
        let vm = makeViewModel { _, _ in nil }
        await vm.loadFirstPage()
        vm.resolveInitialSnapshot(rowCount: 0)
        XCTAssertEqual(vm.loadState, .empty)
    }

    /// Regression: when the first observed snapshot is empty (it arrives before
    /// the tracked fetch persists posts) and the posts show up in a later
    /// snapshot, resolving on that later snapshot must settle the load. The view
    /// controller now calls `resolveInitialSnapshot` on every snapshot for
    /// exactly this reason - gating it to the first snapshot left `loadState`
    /// stuck at `.loading` forever on feeds whose first snapshot is empty (e.g.
    /// the Saved feed), so the skeleton and the pull-to-refresh spinner never
    /// cleared.
    func testLaterNonEmptySnapshotResolvesLoadedAfterEmptyFirstSnapshot() {
        let vm = makeViewModel { _, _ in nil }
        // First (empty) snapshot, before any fetch has completed: stays loading.
        vm.resolveInitialSnapshot(rowCount: 0)
        XCTAssertEqual(vm.loadState, .loading(slow: false))
        // Posts arrive in a later snapshot: the load must now settle.
        vm.resolveInitialSnapshot(rowCount: 4)
        XCTAssertEqual(vm.loadState, .loaded)
    }

    func testThrownURLErrorBecomesFailedUnreachable() async {
        let vm = makeViewModel { _, _ in throw URLError(.timedOut) }
        await vm.loadFirstPage()
        XCTAssertEqual(vm.loadState, .failed(LoadFailure(kind: .unreachable, diagnostics: vm.lastFailureDiagnostics ?? "")))
    }

    func testOfflineMonitorClassifiesFailureAsOffline() async {
        let monitor = StaticReachabilityMonitor(isOnline: false)
        let vm = makeViewModel(reachabilityMonitor: monitor) { _, _ in throw URLError(.timedOut) }
        await vm.loadFirstPage()
        guard case let .failed(failure) = vm.loadState else { return XCTFail("expected failed") }
        XCTAssertEqual(failure.kind, .offline)
    }

    func testHardCapTimesOutToUnreachable() async {
        let vm = makeViewModel(hardCapTimeout: .milliseconds(50)) { _, _ in
            try await Task.sleep(for: .seconds(10))
            return nil
        }
        await vm.loadFirstPage()
        guard case let .failed(failure) = vm.loadState else { return XCTFail("expected failed") }
        XCTAssertEqual(failure.kind, .unreachable)
    }

    func testSlowHintFiresWhileStillLoading() async {
        let started = expectation(description: "fetch started")
        var release: CheckedContinuation<String?, Error>?
        let vm = makeViewModel { _, _ in
            started.fulfill()
            return try await withCheckedThrowingContinuation { release = $0 }
        }
        let task = Task { await vm.loadFirstPage() }
        await fulfillment(of: [started], timeout: 1)

        // Wait past the 20ms slow threshold.
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(vm.loadState, .loading(slow: true))

        release?.resume(returning: nil)
        await task.value
    }

    func testPaginationFailsThenRetrySucceeds() async {
        var callCount = 0
        let vm = makeViewModel { _, _ in
            callCount += 1
            if callCount == 2 { throw URLError(.timedOut) }
            return "next"
        }
        await vm.loadFirstPage() // call 1: succeeds
        vm.resolveInitialSnapshot(rowCount: 2)
        XCTAssertEqual(vm.loadState, .loaded)

        await vm.loadMore() // call 2: throws
        XCTAssertEqual(vm.paginationState, .failed)

        await vm.retryPagination() // call 3: succeeds
        XCTAssertEqual(vm.paginationState, .idle)
    }

    func testPrepareForReloadResetsFailedToLoading() async {
        let vm = makeViewModel { _, _ in throw URLError(.timedOut) }
        await vm.loadFirstPage()
        guard case .failed = vm.loadState else { return XCTFail("expected failed") }
        vm.prepareForReload()
        XCTAssertEqual(vm.loadState, .loading(slow: false))
        XCTAssertEqual(vm.paginationState, .idle)
    }

    func testFailInitialLoadMarksFailedUnreachable() {
        let vm = makeViewModel { _, _ in nil }
        vm.failInitialLoad()
        guard case let .failed(failure) = vm.loadState else { return XCTFail("expected failed") }
        XCTAssertEqual(failure.kind, .unreachable)
        XCTAssertNotNil(vm.lastFailureDiagnostics)
    }

    func testInternalInconsistencyBecomesFailedUnreachable() async {
        let vm = makeViewModel { _, _ in throw LemmyServiceError.internalInconsistency(description: "") }
        await vm.loadFirstPage()
        guard case let .failed(failure) = vm.loadState else { return XCTFail("expected failed") }
        XCTAssertEqual(failure.kind, .unreachable)
    }

    /// Regression: switching the feed in place (the feed switcher reuses this
    /// view model via `showFeed`) mints a fresh UUID feedKey. The fetch must
    /// follow `self.feed` to the new key; if it keeps fetching the feed captured
    /// at init, the page is persisted under the stale key and the observed feed
    /// stays empty - the "all feeds show empty" bug.
    func testFetchTargetsCurrentFeedAfterSwitch() async {
        var fetchedFeedKeys: [String] = []
        let vm = makeViewModel { feed, _ in
            fetchedFeedKeys.append(feed.feedKey)
            return nil
        }

        await vm.loadFirstPage()
        XCTAssertEqual(fetchedFeedKeys, ["feed-1"])

        vm.switchFeed(to: .saved(sortType: .Active))
        await vm.loadFirstPage()

        XCTAssertEqual(fetchedFeedKeys.count, 2)
        XCTAssertEqual(fetchedFeedKeys[1], vm.feed.feedKey, "fetch after switch must target the new feed")
        XCTAssertNotEqual(fetchedFeedKeys[1], "feed-1", "fetch must not reuse the feed captured at init")
    }
}
