//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Per-account exponential back-off for scheduler site-info fetches (in-memory).
/// Pure value type: all time comes in as a `now` parameter so it is fully testable.
struct SchedulerBackoff {
    private struct Entry {
        var failureCount: Int
        var nextAttemptAt: Date
    }

    private var entries: [String: Entry] = [:]

    /// Back-off schedule in scheduler-time: ~5 min, doubling, capped at ~2 h.
    /// failureCount 1→5m, 2→10m, 3→20m, 4→40m, 5→80m, 6+→120m (cap).
    static func backoffDelay(failureCount: Int) -> TimeInterval {
        let base: TimeInterval = 5 * 60
        let cap: TimeInterval = 2 * 60 * 60
        let doublings = max(0, failureCount - 1)
        return min(cap, base * pow(2, Double(doublings)))
    }

    /// True when the account may be attempted now (no entry, or `now` past its window).
    func shouldAttempt(keychainId: String, now: Date) -> Bool {
        guard let entry = entries[keychainId] else { return true }
        return now >= entry.nextAttemptAt
    }

    /// Record a fetch outcome: success clears back-off; failure increments and reschedules.
    mutating func recordResult(keychainId: String, succeeded: Bool, now: Date) {
        if succeeded {
            entries[keychainId] = nil
        } else {
            let count = (entries[keychainId]?.failureCount ?? 0) + 1
            entries[keychainId] = Entry(
                failureCount: count,
                nextAttemptAt: now.addingTimeInterval(Self.backoffDelay(failureCount: count))
            )
        }
    }

    /// Clear all back-off (used on reconnect).
    mutating func reset() {
        entries.removeAll()
    }
}
