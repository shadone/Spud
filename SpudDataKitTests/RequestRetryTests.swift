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

    private actor Recorder {
        var values: [Duration] = []
        func append(_ d: Duration) {
            values.append(d)
        }
    }
}
