//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct SchedulerBackoffTests {
    @Test
    func backoffDelay_schedule() {
        #expect(SchedulerBackoff.backoffDelay(failureCount: 1) == 5 * 60)
        #expect(SchedulerBackoff.backoffDelay(failureCount: 2) == 10 * 60)
        #expect(SchedulerBackoff.backoffDelay(failureCount: 4) == 40 * 60)
        #expect(SchedulerBackoff.backoffDelay(failureCount: 6) == 2 * 60 * 60) // capped
        #expect(SchedulerBackoff.backoffDelay(failureCount: 20) == 2 * 60 * 60) // stays capped
    }

    @Test
    func shouldAttempt_trueWhenNoEntry() {
        let b = SchedulerBackoff()
        #expect(b.shouldAttempt(keychainId: "a", now: Date(timeIntervalSince1970: 0)))
    }

    @Test
    func failure_thenSkippedWithinWindow_thenDueAfter() {
        var b = SchedulerBackoff()
        let t0 = Date(timeIntervalSince1970: 1000)
        b.recordResult(keychainId: "a", succeeded: false, now: t0) // count 1 → +5m
        #expect(!b.shouldAttempt(keychainId: "a", now: t0.addingTimeInterval(60))) // within window
        #expect(b.shouldAttempt(keychainId: "a", now: t0.addingTimeInterval(5 * 60))) // at window
    }

    @Test
    func consecutiveFailures_climb() {
        var b = SchedulerBackoff()
        let t = Date(timeIntervalSince1970: 0)
        b.recordResult(keychainId: "a", succeeded: false, now: t) // 1 → +5m
        b.recordResult(keychainId: "a", succeeded: false, now: t) // 2 → +10m
        #expect(!b.shouldAttempt(keychainId: "a", now: t.addingTimeInterval(9 * 60)))
        #expect(b.shouldAttempt(keychainId: "a", now: t.addingTimeInterval(10 * 60)))
    }

    @Test
    func success_clearsBackoff() {
        var b = SchedulerBackoff()
        let t = Date(timeIntervalSince1970: 0)
        b.recordResult(keychainId: "a", succeeded: false, now: t)
        b.recordResult(keychainId: "a", succeeded: true, now: t)
        #expect(b.shouldAttempt(keychainId: "a", now: t)) // cleared → due
    }

    @Test
    func reset_clearsAll() {
        var b = SchedulerBackoff()
        let t = Date(timeIntervalSince1970: 0)
        b.recordResult(keychainId: "a", succeeded: false, now: t)
        b.reset()
        #expect(b.shouldAttempt(keychainId: "a", now: t))
    }
}
