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
        fetchFeedOperation: @escaping @MainActor (String?) async throws -> String?
    ) -> PostListViewModel {
        let dependencies = TestDependencies(reachabilityMonitor: reachabilityMonitor)
        let feed = FeedHandle(
            feedKey: "feed-1",
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
        let vm = makeViewModel { _ in "next-cursor" }
        await vm.loadFirstPage()
        // Fetch succeeded but rows arrive via GRDB; still loading until snapshot.
        XCTAssertEqual(vm.loadState, .loading(slow: false))
        vm.resolveInitialSnapshot(rowCount: 3)
        XCTAssertEqual(vm.loadState, .loaded)
    }

    func testSuccessWithZeroRowsResolvesEmpty() async {
        let vm = makeViewModel { _ in nil }
        await vm.loadFirstPage()
        vm.resolveInitialSnapshot(rowCount: 0)
        XCTAssertEqual(vm.loadState, .empty)
    }

    func testThrownURLErrorBecomesFailedUnreachable() async {
        let vm = makeViewModel { _ in throw URLError(.timedOut) }
        await vm.loadFirstPage()
        XCTAssertEqual(vm.loadState, .failed(LoadFailure(kind: .unreachable, diagnostics: vm.lastFailureDiagnostics ?? "")))
    }

    func testOfflineMonitorClassifiesFailureAsOffline() async {
        let monitor = StaticReachabilityMonitor(isOnline: false)
        let vm = makeViewModel(reachabilityMonitor: monitor) { _ in throw URLError(.timedOut) }
        await vm.loadFirstPage()
        guard case let .failed(failure) = vm.loadState else { return XCTFail("expected failed") }
        XCTAssertEqual(failure.kind, .offline)
    }

    func testHardCapTimesOutToUnreachable() async {
        let vm = makeViewModel(hardCapTimeout: .milliseconds(50)) { _ in
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
        let vm = makeViewModel { _ in
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
        let vm = makeViewModel { _ in
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
}
