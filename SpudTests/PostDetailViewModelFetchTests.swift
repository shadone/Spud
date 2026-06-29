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
struct PostDetailViewModelFetchTests {
    private struct TestDependencies:
        HasAccountService, HasAlertService, HasPreferencesService, HasReachabilityMonitor
    {
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let preferencesService: PreferencesServiceType
        let reachabilityMonitor: ReachabilityMonitoring

        init(alertService: AlertServiceType, reachabilityMonitor: ReachabilityMonitoring) {
            let appDatabase = try! AppDatabase.inMemory()
            accountService = AccountService(appDatabase: appDatabase)
            self.alertService = alertService
            preferencesService = PreferencesService()
            self.reachabilityMonitor = reachabilityMonitor
        }
    }

    private func makeViewModel(
        alertService: AlertServiceType = AlertService(),
        isOnline: Bool = true,
        reachabilityMonitor: ReachabilityMonitoring? = nil,
        fetchCommentsOperation: @escaping @MainActor (Components.Schemas.CommentSortType) async throws -> Void
    ) -> PostDetailViewModel {
        let dependencies = TestDependencies(
            alertService: alertService,
            reachabilityMonitor: reachabilityMonitor ?? StaticReachabilityMonitor(isOnline: isOnline)
        )
        return PostDetailViewModel(
            serverPostId: 1,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: "kc-1"),
            dependencies: dependencies,
            fetchCommentsOperation: fetchCommentsOperation
        )
    }

    @Test
    func loadingFlagTrueWhileFetchingThenFalse() async {
        var release: CheckedContinuation<Void, Never>?
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let vm = makeViewModel { _ in
            startedContinuation.yield(())
            await withCheckedContinuation { release = $0 }
        }
        let fetchTask = Task { await vm.fetchComments() }
        for await _ in started {
            break
        } // wait until the fetch has started
        #expect(vm.isLoadingComments)

        release?.resume()
        await fetchTask.value
        #expect(!vm.isLoadingComments)
    }

    @Test
    func cancelAndReplaceKeepsFlagAndSilencesSupersededFetch() async {
        var release1: CheckedContinuation<Void, any Error>?
        var release2: CheckedContinuation<Void, Never>?
        var callCount = 0
        let alert = SpyAlertService()
        let (started1, started1Continuation) = AsyncStream<Void>.makeStream()
        let (started2, started2Continuation) = AsyncStream<Void>.makeStream()

        let vm = makeViewModel(alertService: alert) { _ in
            callCount += 1
            if callCount == 1 {
                started1Continuation.yield(())
                try await withCheckedThrowingContinuation { release1 = $0 }
            } else {
                started2Continuation.yield(())
                await withCheckedContinuation { release2 = $0 }
            }
        }
        let t1 = Task { await vm.fetchComments() }
        for await _ in started1 {
            break
        }

        let t2 = Task { await vm.fetchComments() } // supersedes t1
        for await _ in started2 {
            break
        }
        #expect(vm.isLoadingComments)

        // Release t1 with a cancellation error; as the superseded fetch it must
        // not clear the flag or surface an error.
        release1?.resume(throwing: CancellationError())
        await t1.value
        #expect(vm.isLoadingComments)

        release2?.resume()
        await t2.value
        #expect(!vm.isLoadingComments)
        #expect(alert.handledRequests.isEmpty)
        #expect(vm.commentFetchError == nil, "a superseded fetch must not drive the failed state")
    }

    @Test
    func supersededFetchThrowingNonCancellationErrorIsSilent() async {
        // Production path: LemmyService wraps all errors (including underlying
        // cancellation) as LemmyServiceError, so the superseded task hits the
        // generic `catch` branch — not `catch is CancellationError`. Silence is
        // then enforced by the `!Task.isCancelled` guard. This test covers that path.
        struct Boom: Error { }
        var release1: CheckedContinuation<Void, any Error>?
        var release2: CheckedContinuation<Void, Never>?
        var callCount = 0
        let alert = SpyAlertService()
        let (started1, started1Continuation) = AsyncStream<Void>.makeStream()
        let (started2, started2Continuation) = AsyncStream<Void>.makeStream()

        let vm = makeViewModel(alertService: alert) { _ in
            callCount += 1
            if callCount == 1 {
                started1Continuation.yield(())
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                    release1 = c
                }
            } else {
                started2Continuation.yield(())
                await withCheckedContinuation { release2 = $0 }
            }
        }
        let t1 = Task { await vm.fetchComments() }
        for await _ in started1 {
            break
        }

        let t2 = Task { await vm.fetchComments() } // supersedes t1
        for await _ in started2 {
            break
        }
        #expect(vm.isLoadingComments)

        // Release t1 with a non-cancellation error; it was superseded, so the
        // generic `catch` branch fires but `!Task.isCancelled` silences it.
        release1?.resume(throwing: Boom())
        await t1.value
        #expect(vm.isLoadingComments, "superseded task must not clear the flag")
        #expect(alert.handledRequests.isEmpty, "superseded task must not surface an error")

        release2?.resume()
        await t2.value
        #expect(!vm.isLoadingComments)
        #expect(vm.commentFetchError == nil, "the superseded error must not drive the failed state")
    }

    @Test
    func genuineErrorDrivesInlineFailedStateInsteadOfAlert() async {
        // The initial-load failure path now drives the inline failed state
        // (a truthful "couldn't load comments" surface with Retry) instead of a
        // modal alert. A non-cancelled error sets `commentFetchError` and clears
        // the loading flag; no alert is raised.
        struct Boom: Error { }
        let alert = SpyAlertService()
        let vm = makeViewModel(alertService: alert, isOnline: true) { _ in throw Boom() }

        await vm.fetchComments()

        #expect(!vm.isLoadingComments)
        #expect(alert.handledRequests.isEmpty, "the inline failed state replaces the modal alert")
        // Online + a generic error classifies as unreachable.
        #expect(vm.commentFetchError?.kind == .unreachable)
    }

    @Test
    func offlineFailureClassifiesAsOffline() async {
        // When the reachability monitor reports offline, a fetch failure is
        // classified as `.offline` regardless of the underlying error — driving
        // the "You're offline" inline comments state.
        struct Boom: Error { }
        let vm = makeViewModel(isOnline: false) { _ in throw Boom() }

        await vm.fetchComments()

        #expect(!vm.isLoadingComments)
        #expect(vm.commentFetchError?.kind == .offline)
    }

    @Test
    func successfulFetchHasNoError() async {
        let vm = makeViewModel { _ in }

        await vm.fetchComments()

        #expect(!vm.isLoadingComments)
        #expect(vm.commentFetchError == nil)
    }

    @Test
    func retryAfterFailureClearsErrorOnSuccess() async {
        // A failed fetch sets the error; a subsequent successful fetch (the
        // Retry path) clears it so the comments / empty state can show.
        struct Boom: Error { }
        var shouldThrow = true
        let vm = makeViewModel(isOnline: false) { _ in
            if shouldThrow { throw Boom() }
        }

        await vm.fetchComments()
        #expect(vm.commentFetchError?.kind == .offline)

        shouldThrow = false
        await vm.fetchComments()
        #expect(vm.commentFetchError == nil)
        #expect(!vm.isLoadingComments)
    }

    @Test
    func setCommentSortTypeUpdatesValue() {
        let vm = makeViewModel { _ in }
        vm.setCommentSortType(.New)
        #expect(vm.commentSortType == .New)
    }

    @Test
    func reconnectRetryReFetchesAndClearsTheOfflineFailure() async {
        // End-to-end shape of the post-detail reconnect auto-retry: a fetch fails
        // offline (setting the failed state the offline copy promises to recover
        // from), then connectivity returns and the retry the reachability
        // observation performs re-invokes the fetch and clears the failure. The
        // edge/guard decision itself is covered by CommentsReconnectRetryTests;
        // this verifies the action it triggers (a second `fetchComments`) actually
        // re-runs the operation and resolves the failed state.
        struct Boom: Error { }
        let monitor = StaticReachabilityMonitor(isOnline: false)
        var callCount = 0
        var shouldThrow = true
        let vm = makeViewModel(reachabilityMonitor: monitor) { _ in
            callCount += 1
            if shouldThrow { throw Boom() }
        }

        await vm.fetchComments()
        #expect(callCount == 1)
        #expect(vm.commentFetchError?.kind == .offline)

        // Connectivity returns; the observation would call `fetchComments` again.
        monitor.setOnline(true)
        shouldThrow = false
        await vm.fetchComments()

        #expect(callCount == 2, "the reconnect retry must re-run the comment fetch")
        #expect(vm.commentFetchError == nil, "a successful reconnect retry clears the failed state")
        #expect(!vm.isLoadingComments)
    }
}
