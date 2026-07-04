//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Paces outbound requests for one offline-download run so all workers together
/// never issue requests closer than `minInterval` apart, and a server pushback
/// (429 / 503 / rate-limit) delays every subsequent request by a cool-down.
///
/// The clock (`now`) and the wait (`sleepUntil`) are injected so the pacer is
/// deterministic in tests (a manual clock advances only when asked to wait),
/// mirroring the "time is a parameter" style of `SchedulerBackoff` / `DiagnosticLog`.
///
/// Correctness: `reserve()` — the only actor-isolated step — synchronously bumps
/// `nextPermitAt`; the actual `sleepUntil(deadline)` runs after, NOT while holding
/// the actor, so the pacer never becomes a serial bottleneck for the content
/// phase's concurrent workers.
actor RequestPacer {
    private let minInterval: Duration
    private let now: @Sendable () -> ContinuousClock.Instant
    private let sleepUntil: @Sendable (ContinuousClock.Instant) async throws -> Void
    private var nextPermitAt: ContinuousClock.Instant

    init(
        minInterval: Duration,
        now: @escaping @Sendable () -> ContinuousClock.Instant,
        sleepUntil: @escaping @Sendable (ContinuousClock.Instant) async throws -> Void
    ) {
        self.minInterval = minInterval
        self.now = now
        self.sleepUntil = sleepUntil
        nextPermitAt = now()
    }

    /// Reserve and wait for this request's slot. The first caller does not wait;
    /// each subsequent caller waits until at least `minInterval` after the prior
    /// slot (and past any active pushback cool-down).
    func acquire() async throws {
        let deadline = reserve()
        try await sleepUntil(deadline)
    }

    /// Push every subsequent permit out by `cooldown` from now — used when the
    /// server signals it wants us to slow down (429 / 503 / rate-limit).
    func penalize(_ cooldown: Duration) {
        let candidate = now().advanced(by: cooldown)
        if candidate > nextPermitAt { nextPermitAt = candidate }
    }

    /// Synchronous, actor-isolated slot reservation. Returns the instant this
    /// request may proceed; advances `nextPermitAt` by `minInterval`.
    private func reserve() -> ContinuousClock.Instant {
        let candidate = now()
        let slot = candidate > nextPermitAt ? candidate : nextPermitAt
        nextPermitAt = slot.advanced(by: minInterval)
        return slot
    }
}
