//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// Run `operation`, retrying transient failures (per `OutboxFailureClass`) with
/// bounded jittered exponential back-off. On a server-pushback error
/// (429 / 503 / rate-limit) it also penalizes the shared `pacer` so every other
/// in-flight request observes the cool-down. A permanent error is rethrown
/// immediately; once `maxAttempts` is reached the last error is rethrown.
///
/// Only idempotent reads are wrapped here (feed pages, comment trees, image
/// GETs), so re-running on retry is side-effect-free — unlike the outbox, which
/// guards non-idempotent mutations from re-send.
///
/// - Parameters:
///   - maxAttempts: Total attempts including the first (e.g. 4 = 1 try + 3 retries).
///   - baseDelay: First-retry back-off; doubles each subsequent retry.
///   - maxDelay: Upper bound on the (pre-jitter) back-off.
///   - pushbackCooldown: Applied to `pacer.penalize` on a pushback error.
///   - isOnline: Passed to `OutboxFailureClass.classify`; offline makes everything transient.
///   - sleep: Back-off wait (injected for tests).
///   - jitter: Returns a fraction in the given range; full-jitter scales the delay by it.
///   - onRetry: Notified before each back-off sleep (used to record a diagnostic).
func withRetry<T: Sendable>(
    maxAttempts: Int,
    baseDelay: Duration,
    maxDelay: Duration,
    pushbackCooldown: Duration,
    pacer: RequestPacer,
    isOnline: Bool = true,
    sleep: @Sendable (Duration) async throws -> Void,
    jitter: @Sendable (ClosedRange<Double>) -> Double,
    onRetry: @Sendable (_ attempt: Int, _ delay: Duration, _ error: Error) async -> Void = { _, _, _ in },
    operation: () async throws -> T
) async throws -> T {
    var attempt = 0
    while true {
        attempt += 1
        do {
            return try await operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A cancellation that surfaced as a different error type still means stop.
            try Task.checkCancellation()

            let classification = OutboxFailureClass.classify(error, isOnline: isOnline)
            guard classification == .transient, attempt < maxAttempts else { throw error }

            // Exponential: baseDelay doubled (attempt-1) times, capped, then full-jittered.
            var delay = baseDelay
            for _ in 1..<attempt {
                delay = delay * 2
            }
            if delay > maxDelay { delay = maxDelay }
            let jittered = Duration.seconds(delay.asTimeInterval * jitter(0...1))

            await onRetry(attempt, jittered, error)
            if isServerPushback(error) { await pacer.penalize(pushbackCooldown) }
            try await sleep(jittered)
        }
    }
}

/// True for the "please slow down" server signals: HTTP 429 / 503, or a
/// structured `rate_limit*` Lemmy server error. The broader transient set
/// (other 5xx, timeouts, offline) still retries but does not add a global
/// cool-down.
func isServerPushback(_ error: Error) -> Bool {
    switch error {
    case let serviceError as LemmyServiceError:
        if case let .apiError(api) = serviceError { return isServerPushback(api) }
        return false
    case let api as LemmyApiError:
        return isServerPushback(api)
    default:
        return false
    }
}

private func isServerPushback(_ api: LemmyApiError) -> Bool {
    switch api {
    case let .unknownServerError(httpStatusCode, _):
        return httpStatusCode == 429 || httpStatusCode == 503
    case let .serverError(errorResponse):
        return errorResponse.error.hasPrefix("rate_limit")
    default:
        return false
    }
}

extension Duration {
    /// The duration as fractional seconds. Used to scale a delay by a jitter
    /// fraction (Duration has no built-in `* Double`).
    var asTimeInterval: TimeInterval {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) / 1_000_000_000_000_000_000
    }
}
