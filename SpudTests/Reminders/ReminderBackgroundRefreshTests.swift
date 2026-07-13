//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import BackgroundTasks
import Foundation
import Testing
@testable import Spud

/// Covers `ReminderBackgroundRefresh`'s pure, testable surface (spec §5.3,
/// Phase 4 Task 1): the task identifier and `makeRequest(now:)`'s request
/// construction. `register`/the handler/`schedule` all call into
/// `BGTaskScheduler`, which only does anything meaningful on-device or in a
/// host app under test - there is no in-process fake for it, so that half of
/// this type is verified manually (see the plan's on-device-verify note).
struct ReminderBackgroundRefreshTests {
    @Test
    func taskIdentifierMatchesInfoPlistPermittedIdentifier() {
        // Must stay byte-identical to the `BGTaskSchedulerPermittedIdentifiers`
        // entry in Info.plist - `BGTaskScheduler.register` traps at runtime if
        // an identifier isn't declared there.
        #expect(ReminderBackgroundRefresh.taskIdentifier == "info.ddenis.Spud.reminderPoll")
    }

    @Test
    func makeRequestSetsTheDeclaredIdentifier() {
        let request = ReminderBackgroundRefresh.makeRequest(now: Date())
        #expect(request.identifier == ReminderBackgroundRefresh.taskIdentifier)
    }

    @Test
    func makeRequestSetsEarliestBeginDateToNowPlusRefreshInterval() {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        let request = ReminderBackgroundRefresh.makeRequest(now: now)
        #expect(request.earliestBeginDate == now.addingTimeInterval(ReminderBackgroundRefresh.refreshInterval))
    }

    @Test
    func refreshIntervalIsTwoHours() {
        #expect(ReminderBackgroundRefresh.refreshInterval == 2 * 60 * 60)
    }
}
