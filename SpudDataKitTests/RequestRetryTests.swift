//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

@Suite(.serialized)
struct RequestRetryTests {
    /// A pacer whose waits are instant (real clock, no-op sleep) so penalize can be
    /// observed only via behavior; timing is asserted through the recorded sleeps.
    private func immediatePacer() -> RequestPacer {
        RequestPacer(minInterval: .zero, now: { ContinuousClock().now }, sleepUntil: { _ in })
    }

    private func transient503() -> Error {
        LemmyServiceError.apiError(.unknownServerError(httpStatusCode: 503, error: nil))
    }

    private func permanent403() -> Error {
        LemmyServiceError.apiError(.unknownServerError(httpStatusCode: 403, error: nil))
    }

    @Test
    func retriesTransientThenSucceeds() async throws {
        let recorded = Recorder()
        var calls = 0
        let result = try await withRetry(
            maxAttempts: 4, baseDelay: .milliseconds(500), maxDelay: .seconds(30),
            pushbackCooldown: .seconds(8), pacer: immediatePacer(),
            sleep: { await recorded.append($0) }, jitter: { _ in 1.0 }
        ) {
            calls += 1
            if calls < 3 { throw transient503() }
            return "ok"
        }
        #expect(result == "ok")
        #expect(calls == 3)
        // Two retries: full-jitter delays 500ms, 1000ms.
        let delays = await recorded.values
        #expect(delays == [.milliseconds(500), .milliseconds(1000)])
    }

    @Test
    func permanentErrorIsNotRetried() async throws {
        var calls = 0
        await #expect(throws: LemmyServiceError.self) {
            try await withRetry(
                maxAttempts: 4, baseDelay: .milliseconds(500), maxDelay: .seconds(30),
                pushbackCooldown: .seconds(8), pacer: immediatePacer(),
                sleep: { _ in }, jitter: { _ in 1.0 }
            ) {
                calls += 1
                throw permanent403()
            }
        }
        #expect(calls == 1, "a permanent error must not retry")
    }

    @Test
    func exhaustsAttemptsThenRethrows() async throws {
        var calls = 0
        await #expect(throws: LemmyServiceError.self) {
            try await withRetry(
                maxAttempts: 3, baseDelay: .milliseconds(500), maxDelay: .seconds(30),
                pushbackCooldown: .seconds(8), pacer: immediatePacer(),
                sleep: { _ in }, jitter: { _ in 1.0 }
            ) {
                calls += 1
                throw transient503()
            }
        }
        #expect(calls == 3, "should try exactly maxAttempts times")
    }

    @Test
    func cancellationIsNotRetried() async throws {
        var calls = 0
        await #expect(throws: CancellationError.self) {
            try await withRetry(
                maxAttempts: 4, baseDelay: .milliseconds(500), maxDelay: .seconds(30),
                pushbackCooldown: .seconds(8), pacer: immediatePacer(),
                sleep: { _ in }, jitter: { _ in 1.0 }
            ) {
                calls += 1
                throw CancellationError()
            }
        }
        #expect(calls == 1, "cancellation must propagate immediately, no retry")
    }

    // MARK: - Pushback vs. non-pushback penalize

    /// A server-pushback error (HTTP 503) causes `withRetry` to call
    /// `pacer.penalize(pushbackCooldown)` before sleeping. With a `ManualClock`-backed
    /// pacer (`minInterval: .zero`) the penalty is observable: after `withRetry`
    /// exhausts its attempts, the next `pacer.acquire()` reserves a deadline
    /// ≥ base + pushbackCooldown (i.e. ≥ 8 s ahead).
    ///
    /// `maxAttempts: 2` so the first attempt fails and reaches the retry branch
    /// (where `penalize` lives), then the second attempt fails and the error is
    /// rethrown — one `penalize` call in total.
    @Test
    func pushback503TriggersPacerPenalize() async throws {
        let clock = ManualClock()
        let pacer = RequestPacer(minInterval: .zero, now: clock.now, sleepUntil: clock.sleepUntil)

        // 503 is transient, so attempt 1 enters the retry branch, calls penalize,
        // sleeps (no-op), then attempt 2 fails and is rethrown (2 < 2 is false).
        await #expect(throws: LemmyServiceError.self) {
            try await withRetry(
                maxAttempts: 2, baseDelay: .milliseconds(500), maxDelay: .seconds(30),
                pushbackCooldown: .seconds(8), pacer: pacer,
                sleep: { _ in }, jitter: { _ in 1.0 }
            ) {
                throw transient503()
            }
        }

        // Acquire once to observe what deadline the pacer will reserve.
        try await pacer.acquire()

        #expect(clock.reservedDeadlines.count == 1)
        let elapsed = clock.base.duration(to: clock.reservedDeadlines[0])
        #expect(elapsed >= .seconds(8), "a 503 pushback must penalize the pacer by the cooldown")
    }

    /// A transient but non-pushback error (`URLError(.timedOut)`) causes `withRetry`
    /// to retry with back-off delay, but must NOT call `pacer.penalize`. After
    /// `withRetry` exhausts its attempts the next `pacer.acquire()` sees
    /// `nextPermitAt` still at its initial value (deadline ≈ base).
    @Test
    func nonPushbackTransientDoesNotPenalizePacer() async throws {
        let clock = ManualClock()
        let pacer = RequestPacer(minInterval: .zero, now: clock.now, sleepUntil: clock.sleepUntil)

        // URLError(.timedOut) is transient but NOT a pushback — withRetry retries
        // it (attempt 1 enters retry branch, no penalize, sleeps no-op) but
        // never calls pacer.penalize. Attempt 2 fails and is rethrown.
        await #expect(throws: URLError.self) {
            try await withRetry(
                maxAttempts: 2, baseDelay: .milliseconds(500), maxDelay: .seconds(30),
                pushbackCooldown: .seconds(8), pacer: pacer,
                sleep: { _ in }, jitter: { _ in 1.0 }
            ) {
                throw URLError(.timedOut)
            }
        }

        // Acquire once to observe the pacer's deadline.
        try await pacer.acquire()

        #expect(clock.reservedDeadlines.count == 1)
        let elapsed = clock.base.duration(to: clock.reservedDeadlines[0])
        #expect(elapsed < .seconds(1), "a non-pushback transient must not penalize the pacer")
    }

    private actor Recorder {
        var values: [Duration] = []
        func append(_ d: Duration) {
            values.append(d)
        }
    }
}
