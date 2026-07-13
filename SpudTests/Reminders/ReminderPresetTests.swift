//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud

/// Covers `ReminderPreset.resolvedDate(now:calendar:)` and
/// `validCustomReminderDate` (spec §2.4). Every case injects a fixed `now`
/// and a fixed-timezone `Calendar` so the math is deterministic regardless of
/// the host machine's locale/timezone/DST.
struct ReminderPresetTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// Builds a `Date` for `year`-`month`-`day` at `hour`:`minute` in the fixed calendar.
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    @Test
    func inThreeHoursIsNowPlusThreeHours() {
        let now = date(2026, 7, 13, 10)
        let resolved = ReminderPreset.inThreeHours.resolvedDate(now: now, calendar: calendar)
        #expect(resolved == date(2026, 7, 13, 13))
    }

    @Test
    func thisEveningBeforeSeventeenIsTodayAtEighteen() {
        let now = date(2026, 7, 13, 10)
        let resolved = ReminderPreset.thisEvening.resolvedDate(now: now, calendar: calendar)
        #expect(resolved == date(2026, 7, 13, 18))
    }

    @Test
    func thisEveningAfterSeventeenIsNowPlusThreeHours() {
        let now = date(2026, 7, 13, 19)
        let resolved = ReminderPreset.thisEvening.resolvedDate(now: now, calendar: calendar)
        #expect(resolved == date(2026, 7, 13, 22))
    }

    @Test
    func thisEveningAtExactlySeventeenIsNowPlusThreeHours() {
        // The boundary itself counts as "already past ~17:00" - falls through
        // to now+3h rather than the (only-1-hour-away) 18:00 slot.
        let now = date(2026, 7, 13, 17)
        let resolved = ReminderPreset.thisEvening.resolvedDate(now: now, calendar: calendar)
        #expect(resolved == date(2026, 7, 13, 20))
    }

    @Test
    func tomorrowIsNextDayAtNine() {
        let now = date(2026, 7, 13, 10)
        let resolved = ReminderPreset.tomorrow.resolvedDate(now: now, calendar: calendar)
        #expect(resolved == date(2026, 7, 14, 9))
    }

    @Test
    func inTwoDaysIsTwoDaysAheadAtNine() {
        let now = date(2026, 7, 13, 10)
        let resolved = ReminderPreset.inTwoDays.resolvedDate(now: now, calendar: calendar)
        #expect(resolved == date(2026, 7, 15, 9))
    }

    @Test
    func inAWeekIsSevenDaysAheadAtNine() {
        let now = date(2026, 7, 13, 10)
        let resolved = ReminderPreset.inAWeek.resolvedDate(now: now, calendar: calendar)
        #expect(resolved == date(2026, 7, 20, 9))
    }

    @Test(arguments: ReminderPreset.allCases)
    func everyPresetResolvesStrictlyAfterNow(preset: ReminderPreset) {
        let now = date(2026, 7, 13, 10)
        let resolved = preset.resolvedDate(now: now, calendar: calendar)
        #expect(resolved > now)
    }

    @Test(arguments: ReminderPreset.allCases)
    func everyPresetResolvesStrictlyAfterNowLateInTheEvening(preset: ReminderPreset) {
        // Also exercises thisEvening's "already past 17:00" branch, where the
        // naive "today 18:00" slot would otherwise be in the past.
        let now = date(2026, 7, 13, 23)
        let resolved = preset.resolvedDate(now: now, calendar: calendar)
        #expect(resolved > now)
    }

    @Test
    func validCustomReminderDateRejectsPastDate() {
        let now = date(2026, 7, 13, 10)
        let past = date(2026, 7, 13, 9)
        #expect(validCustomReminderDate(past, now: now) == nil)
    }

    @Test
    func validCustomReminderDateRejectsExactlyNow() {
        let now = date(2026, 7, 13, 10)
        #expect(validCustomReminderDate(now, now: now) == nil)
    }

    @Test
    func validCustomReminderDateAcceptsFutureDate() {
        let now = date(2026, 7, 13, 10)
        let future = date(2026, 7, 13, 11)
        #expect(validCustomReminderDate(future, now: now) == future)
    }
}
