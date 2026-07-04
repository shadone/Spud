//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A controllable clock for `RequestPacer`: `now` advances only when `sleepUntil`
/// is asked to wait, so tests never wait in real time yet observe the exact
/// deadlines the pacer reserved.
final class ManualClock: @unchecked Sendable {
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
