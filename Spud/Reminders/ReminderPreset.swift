//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A quick "Remind Me…" time preset offered on the whole-post reminder menu
/// (spec §2.4). `CaseIterable`'s declaration order is the menu's canonical
/// display order.
enum ReminderPreset: CaseIterable {
    case inThreeHours
    case thisEvening
    case tomorrow
    case inTwoDays
    case inAWeek

    /// The localized menu item label for this preset.
    var menuTitle: String {
        switch self {
        case .inThreeHours:
            NSLocalizedString("In 3 hours", comment: "Reminder time preset")
        case .thisEvening:
            NSLocalizedString("This evening", comment: "Reminder time preset")
        case .tomorrow:
            NSLocalizedString("Tomorrow", comment: "Reminder time preset")
        case .inTwoDays:
            NSLocalizedString("In 2 days", comment: "Reminder time preset")
        case .inAWeek:
            NSLocalizedString("In a week", comment: "Reminder time preset")
        }
    }

    /// Resolves this preset to an absolute fire date (spec §2.4). Pure - takes
    /// `now`/`calendar` as parameters rather than reading `Date()`/`.current`
    /// itself, so it's deterministically unit-testable and never race-prone
    /// under Swift 6 strict concurrency. The caller passes `Date()`/`.current`.
    ///
    /// `thisEvening` returns today 18:00 unless `now` is already at or past
    /// 17:00, in which case it falls back to `now + 3h` - so it never resolves
    /// to a past or imminent fire once evening is already underway.
    func resolvedDate(now: Date, calendar: Calendar) -> Date {
        switch self {
        case .inThreeHours:
            Self.addingHours(3, to: now, calendar: calendar)

        case .thisEvening:
            if calendar.component(.hour, from: now) >= 17 {
                Self.addingHours(3, to: now, calendar: calendar)
            } else {
                calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? Self.addingHours(3, to: now, calendar: calendar)
            }

        case .tomorrow:
            Self.morning(daysFromNow: 1, now: now, calendar: calendar)

        case .inTwoDays:
            Self.morning(daysFromNow: 2, now: now, calendar: calendar)

        case .inAWeek:
            Self.morning(daysFromNow: 7, now: now, calendar: calendar)
        }
    }

    private static func addingHours(_ hours: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .hour, value: hours, to: date) ?? date.addingTimeInterval(TimeInterval(hours) * 3600)
    }

    /// 09:00 on the day `days` after `now`'s day.
    private static func morning(daysFromNow days: Int, now: Date, calendar: Calendar) -> Date {
        let targetDay = calendar.date(byAdding: .day, value: days, to: now) ?? now.addingTimeInterval(TimeInterval(days) * 86400)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: targetDay) ?? targetDay
    }
}

/// Validates a user-picked custom reminder date (the "Pick a time…" menu
/// item): returns `date` iff it's strictly in the future relative to `now`,
/// rejecting a past or exactly-`now` pick (spec §2.4).
func validCustomReminderDate(_ date: Date, now: Date) -> Date? {
    date > now ? date : nil
}
