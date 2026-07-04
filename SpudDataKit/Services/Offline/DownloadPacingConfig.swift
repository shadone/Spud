//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Tunables and injectable time/randomness for one offline-download run's
/// request pacing + retry. `.live` carries the shipping defaults; tests swap in
/// no-wait sleeps and a fixed jitter (see the `immediate` test factory).
public struct DownloadPacingConfig: Sendable {
    /// Minimum spacing between request kickoffs across ALL workers (the proactive throttle).
    public var minRequestInterval: Duration
    /// Total attempts (incl. the first) for a feed-page or comment fetch.
    public var maxRetryAttempts: Int
    /// Total attempts for an image warm — lower, since an image failure carries no
    /// classifiable error (a non-`ready` stream is treated as one transient blip).
    public var maxImageRetryAttempts: Int
    /// First-retry back-off; doubles each retry, capped at `retryMaxDelay`.
    public var retryBaseDelay: Duration
    /// Upper bound on the (pre-jitter) exponential back-off delay.
    public var retryMaxDelay: Duration
    /// Global cool-down injected into the pacer on a 429 / 503 / rate-limit.
    public var serverPushbackCooldown: Duration

    public var now: @Sendable () -> ContinuousClock.Instant
    public var sleepUntil: @Sendable (ContinuousClock.Instant) async throws -> Void
    public var sleep: @Sendable (Duration) async throws -> Void
    public var jitter: @Sendable (ClosedRange<Double>) -> Double

    public init(
        minRequestInterval: Duration,
        maxRetryAttempts: Int,
        maxImageRetryAttempts: Int,
        retryBaseDelay: Duration,
        retryMaxDelay: Duration,
        serverPushbackCooldown: Duration,
        now: @escaping @Sendable () -> ContinuousClock.Instant,
        sleepUntil: @escaping @Sendable (ContinuousClock.Instant) async throws -> Void,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        jitter: @escaping @Sendable (ClosedRange<Double>) -> Double
    ) {
        self.minRequestInterval = minRequestInterval
        self.maxRetryAttempts = maxRetryAttempts
        self.maxImageRetryAttempts = maxImageRetryAttempts
        self.retryBaseDelay = retryBaseDelay
        self.retryMaxDelay = retryMaxDelay
        self.serverPushbackCooldown = serverPushbackCooldown
        self.now = now
        self.sleepUntil = sleepUntil
        self.sleep = sleep
        self.jitter = jitter
    }

    /// Shipping defaults (spec §4).
    public static let live = DownloadPacingConfig(
        minRequestInterval: .milliseconds(200),
        maxRetryAttempts: 4,
        maxImageRetryAttempts: 2,
        retryBaseDelay: .milliseconds(500),
        retryMaxDelay: .seconds(30),
        serverPushbackCooldown: .seconds(8),
        now: { ContinuousClock().now },
        sleepUntil: { try await ContinuousClock().sleep(until: $0) },
        sleep: { try await Task.sleep(for: $0) },
        jitter: { Double.random(in: $0) }
    )
}
