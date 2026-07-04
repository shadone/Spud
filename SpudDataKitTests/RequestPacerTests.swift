//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

/// A controllable clock for `RequestPacer`: `now` advances only when `sleepUntil`
/// is asked to wait, so tests never wait in real time yet observe the exact
/// deadlines the pacer reserved.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: ContinuousClock.Instant
    private(set) var reservedDeadlines: [ContinuousClock.Instant] = []
    let base: ContinuousClock.Instant

    init() {
        let start = ContinuousClock().now
        base = start
        current = start
    }

    var now: @Sendable () -> ContinuousClock.Instant {
        { [self] in lock.withLock { current } }
    }

    var sleepUntil: @Sendable (ContinuousClock.Instant) async throws -> Void {
        { [self] deadline in
            lock.withLock {
                reservedDeadlines.append(deadline)
                if deadline > current { current = deadline }
            }
        }
    }
}

@Suite(.serialized)
struct RequestPacerTests {
    @Test
    func firstAcquireDoesNotWaitThenSpacesByInterval() async throws {
        let clock = ManualClock()
        let pacer = RequestPacer(minInterval: .milliseconds(200), now: clock.now, sleepUntil: clock.sleepUntil)

        try await pacer.acquire()
        try await pacer.acquire()
        try await pacer.acquire()

        #expect(clock.reservedDeadlines.count == 3)
        // First slot is "now" (no wait); each subsequent slot steps by minInterval.
        #expect(clock.base.duration(to: clock.reservedDeadlines[0]) == .zero)
        #expect(clock.reservedDeadlines[0].duration(to: clock.reservedDeadlines[1]) == .milliseconds(200))
        #expect(clock.reservedDeadlines[1].duration(to: clock.reservedDeadlines[2]) == .milliseconds(200))
    }

    @Test
    func penalizePushesNextSlotOutByCooldown() async throws {
        let clock = ManualClock()
        let pacer = RequestPacer(minInterval: .milliseconds(200), now: clock.now, sleepUntil: clock.sleepUntil)

        try await pacer.acquire() // slot 0 at base
        await pacer.penalize(.seconds(8)) // next slot must jump to now+8s
        try await pacer.acquire() // slot 1

        let gap = clock.reservedDeadlines[0].duration(to: clock.reservedDeadlines[1])
        #expect(gap >= .seconds(8), "penalize should push the next slot out by the cooldown")
    }
}
