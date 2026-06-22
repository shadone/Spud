//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import XCTest
@testable import Spud

/// Counts error-handling calls so the cancel-and-replace tests can assert a
/// superseded fetch does not surface an error.
private final class SpyAlertService: AlertServiceType, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [AlertHandlerRequest] = []
    var handledRequests: [AlertHandlerRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    func handle(_ error: Error, for request: AlertHandlerRequest) {
        lock.lock()
        _requests.append(request)
        lock.unlock()
    }

    func image(error: ImageLoadingError, for imageUrl: URL) { }
}

@MainActor
final class PostDetailViewModelFetchTests: XCTestCase {
    private struct TestDependencies:
        HasAccountService, HasAlertService, HasPreferencesService
    {
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let preferencesService: PreferencesServiceType

        init(alertService: AlertServiceType) {
            let appDatabase = try! AppDatabase.inMemory()
            accountService = AccountService(appDatabase: appDatabase)
            self.alertService = alertService
            preferencesService = PreferencesService()
        }
    }

    private func makeViewModel(
        alertService: AlertServiceType = AlertService(),
        fetchCommentsOperation: @escaping @MainActor (Components.Schemas.CommentSortType) async throws -> Void
    ) -> PostDetailViewModel {
        let dependencies = TestDependencies(alertService: alertService)
        return PostDetailViewModel(
            serverPostId: 1,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: "kc-1"),
            dependencies: dependencies,
            fetchCommentsOperation: fetchCommentsOperation
        )
    }

    func testLoadingFlagTrueWhileFetchingThenFalse() async {
        var release: CheckedContinuation<Void, Never>?
        let started = expectation(description: "operation started")
        let vm = makeViewModel { _ in
            started.fulfill()
            await withCheckedContinuation { release = $0 }
        }

        let task = Task { await vm.fetchComments() }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(vm.isLoadingComments)

        release?.resume()
        await task.value
        XCTAssertFalse(vm.isLoadingComments)
    }

    func testCancelAndReplaceKeepsFlagAndSilencesSupersededFetch() async {
        var release1: CheckedContinuation<Void, any Error>?
        var release2: CheckedContinuation<Void, Never>?
        let started1 = expectation(description: "op1 started")
        let started2 = expectation(description: "op2 started")
        var callCount = 0
        let alert = SpyAlertService()

        let vm = makeViewModel(alertService: alert) { _ in
            callCount += 1
            if callCount == 1 {
                started1.fulfill()
                try await withCheckedThrowingContinuation { release1 = $0 }
            } else {
                started2.fulfill()
                await withCheckedContinuation { release2 = $0 }
            }
        }

        let t1 = Task { await vm.fetchComments() }
        await fulfillment(of: [started1], timeout: 1)

        let t2 = Task { await vm.fetchComments() } // supersedes t1
        await fulfillment(of: [started2], timeout: 1)
        XCTAssertTrue(vm.isLoadingComments)

        // Release t1 with a cancellation error; as the superseded fetch it must
        // not clear the flag or surface an error.
        release1?.resume(throwing: CancellationError())
        await t1.value
        XCTAssertTrue(vm.isLoadingComments)

        release2?.resume()
        await t2.value
        XCTAssertFalse(vm.isLoadingComments)
        XCTAssertTrue(alert.handledRequests.isEmpty)
    }

    func testSupersededFetchThrowingNonCancellationErrorIsSilent() async {
        // Production path: LemmyService wraps all errors (including underlying
        // cancellation) as LemmyServiceError, so the superseded task hits the
        // generic `catch` branch — not `catch is CancellationError`. Silence is
        // then enforced by the `!Task.isCancelled` guard. This test covers that path.
        struct Boom: Error { }
        var release1: CheckedContinuation<Void, any Error>?
        var release2: CheckedContinuation<Void, Never>?
        let started1 = expectation(description: "op1 started")
        let started2 = expectation(description: "op2 started")
        var callCount = 0
        let alert = SpyAlertService()

        let vm = makeViewModel(alertService: alert) { _ in
            callCount += 1
            if callCount == 1 {
                started1.fulfill()
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                    release1 = c
                }
            } else {
                started2.fulfill()
                await withCheckedContinuation { release2 = $0 }
            }
        }

        let t1 = Task { await vm.fetchComments() }
        await fulfillment(of: [started1], timeout: 1)

        let t2 = Task { await vm.fetchComments() } // supersedes t1
        await fulfillment(of: [started2], timeout: 1)
        XCTAssertTrue(vm.isLoadingComments)

        // Release t1 with a non-cancellation error; it was superseded, so the
        // generic `catch` branch fires but `!Task.isCancelled` silences it.
        release1?.resume(throwing: Boom())
        await t1.value
        XCTAssertTrue(vm.isLoadingComments, "superseded task must not clear the flag")
        XCTAssertTrue(alert.handledRequests.isEmpty, "superseded task must not surface an error")

        release2?.resume()
        await t2.value
        XCTAssertFalse(vm.isLoadingComments)
    }

    func testGenuineErrorIsSurfacedAndClearsFlag() async {
        struct Boom: Error { }
        let alert = SpyAlertService()
        let vm = makeViewModel(alertService: alert) { _ in throw Boom() }

        await vm.fetchComments()

        XCTAssertFalse(vm.isLoadingComments)
        XCTAssertEqual(alert.handledRequests, [.fetchComments])
    }

    func testSetCommentSortTypeUpdatesValue() {
        let vm = makeViewModel { _ in }
        vm.setCommentSortType(.New)
        XCTAssertEqual(vm.commentSortType, .New)
    }
}
