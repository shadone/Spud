//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

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

    /// `penalize(.zero)` must never rewind an established schedule: the candidate
    /// `now + .zero == now` is always <= the accumulated `nextPermitAt`, so the
    /// guard `candidate > nextPermitAt` is false and the slot is left untouched.
    /// In other words, a zero-cooldown penalty is a no-op for future slots.
    @Test
    func penalizeWithZeroCooldownDoesNotRewindSchedule() async throws {
        let clock = ManualClock()
        // Use a 200 ms interval so the schedule accumulates quickly.
        let pacer = RequestPacer(minInterval: .milliseconds(200), now: clock.now, sleepUntil: clock.sleepUntil)

        // Build up a schedule: base, base+200ms, base+400ms, base+600ms.
        try await pacer.acquire() // slot 0
        try await pacer.acquire() // slot 1
        try await pacer.acquire() // slot 2
        try await pacer.acquire() // slot 3

        // Penalize with .zero — this must be a no-op (candidate = now = base+600ms
        // which equals nextPermitAt, so candidate > nextPermitAt is false).
        await pacer.penalize(.zero)

        // The next slot must still be spaced by minInterval from the existing
        // schedule, not pulled back to "now".
        try await pacer.acquire() // slot 4

        #expect(clock.reservedDeadlines.count == 5)
        // Slot 3 to slot 4 must be exactly minInterval (the zero-cooldown penalty
        // must not have rewound nextPermitAt to an earlier position).
        let gap = clock.reservedDeadlines[3].duration(to: clock.reservedDeadlines[4])
        #expect(gap == .milliseconds(200), "zero-cooldown penalize must not rewind the schedule")
    }
}
