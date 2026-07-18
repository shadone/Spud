//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import os.log

private let logger = Logger(subsystem: "info.ddenis.Spud", category: "StatsService")

/// The single write path for device-wide fun stats. See the design spec
/// (docs/superpowers/specs/2026-07-18-fun-stats-design.md) for semantics.
public protocol StatsServicing: Sendable {
    /// Adds `amount` to `key`'s current (day, hour) bucket. Buffered in
    /// memory; a no-op while collection is disabled.
    func record(_ key: FunStatKey, amount: Double) async

    /// Enables or disables collection. Disabling drops any buffered values.
    func setEnabled(_ isEnabled: Bool) async

    /// Writes buffered values to the database (best-effort) and clears the buffer.
    func flush() async

    /// Deletes all persisted stats and drops the buffer. Backs "Reset Stats".
    func resetAllStats() async

    /// Scene became active: counts a new session when the app was away longer
    /// than the session gap, and starts the foreground-time stopwatch.
    func appDidBecomeActive() async

    /// Scene resigns active: banks elapsed foreground seconds and flushes.
    func appWillResignActive() async
}

public extension StatsServicing {
    func record(_ key: FunStatKey) async {
        await record(key, amount: 1)
    }
}

public protocol HasStatsService {
    var statsService: StatsServicing { get }
}

public actor StatsService: StatsServicing {
    private let appDatabase: AppDatabase
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let flushDelay: Duration
    private let sessionGap: TimeInterval

    private var isEnabled = true
    private var buffer: [FunStatBucket: [FunStatKey: Double]] = [:]
    private var flushTask: Task<Void, Never>?

    /// Bumped by `resetAllStats()` only. Actor re-entrancy means a `performFlush()`
    /// already suspended on the DB write can still be in flight when a reset runs;
    /// without this guard the writer could enqueue the reset's `clearFunStats()`
    /// before that in-flight `incrementFunStats()`, so pre-reset deltas land after
    /// the clear and silently survive a user-facing "Reset Stats". `performFlush()`
    /// snapshots this before its write await and, if it changed by the time the
    /// write returns, issues a compensating clear so reset always wins.
    private var generation = 0

    private var becameActiveAt: Date?
    private var lastResignActiveAt: Date?

    public init(
        appDatabase: AppDatabase,
        now: @Sendable @escaping () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent,
        flushDelay: Duration = .seconds(10),
        sessionGap: TimeInterval = 300
    ) {
        self.appDatabase = appDatabase
        self.now = now
        self.calendar = calendar
        self.flushDelay = flushDelay
        self.sessionGap = sessionGap
    }

    public func record(_ key: FunStatKey, amount: Double) {
        guard isEnabled, amount > 0 else { return }
        let bucket = FunStatBucket.make(date: now(), calendar: calendar)
        buffer[bucket, default: [:]][key, default: 0] += amount
        scheduleFlush()
    }

    public func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        if !isEnabled {
            buffer.removeAll()
            flushTask?.cancel()
            flushTask = nil
        }
    }

    public func flush() async {
        flushTask?.cancel()
        flushTask = nil
        await performFlush()
    }

    public func resetAllStats() async {
        // Bump first so a `performFlush()` already suspended on its DB write
        // (see `generation`'s doc) observes the reset when it resumes.
        generation += 1
        buffer.removeAll()
        flushTask?.cancel()
        flushTask = nil
        do {
            try await appDatabase.clearFunStats()
        } catch {
            logger.error("resetAllStats failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func appDidBecomeActive() {
        guard becameActiveAt == nil else { return }
        let current = now()
        let isNewSession: Bool
        if let lastResignActiveAt {
            isNewSession = current.timeIntervalSince(lastResignActiveAt) > sessionGap
        } else {
            isNewSession = true
        }
        if isNewSession {
            record(.sessionCount, amount: 1)
        }
        becameActiveAt = current
    }

    public func appWillResignActive() async {
        let current = now()
        if let becameActiveAt {
            record(.foregroundSeconds, amount: current.timeIntervalSince(becameActiveAt))
        }
        becameActiveAt = nil
        lastResignActiveAt = current
        await flush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [flushDelay] in
            try? await Task.sleep(for: flushDelay)
            guard !Task.isCancelled else { return }
            await self.timerFlush()
        }
    }

    private func timerFlush() async {
        flushTask = nil
        await performFlush()
    }

    private func performFlush() async {
        guard !buffer.isEmpty else { return }
        let deltas = buffer.flatMap { bucket, values in
            values.map { key, value in
                FunStatDelta(day: bucket.day, hour: bucket.hour, key: key.rawValue, value: value)
            }
        }
        buffer.removeAll()
        // Snapshot before the write suspends this task: actor re-entrancy lets
        // resetAllStats() run while we're awaiting the DB writer, and depending
        // on task-hop timing its clearFunStats() could otherwise be enqueued
        // before this increment, letting pre-reset deltas land after the clear.
        let gen = generation
        // Best-effort: a stats write failure must never affect the app. The
        // buffered deltas are simply lost.
        do {
            try await appDatabase.incrementFunStats(deltas)
        } catch {
            logger.error("fun stats flush failed: \(String(describing: error), privacy: .public)")
        }
        if generation != gen {
            // A reset interleaved with this write. Make reset win by
            // compensating with a clear, even though our increment already landed.
            try? await appDatabase.clearFunStats()
        }
    }
}
