//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// How long a community mute lasts. Muting is a client-local view concern, so
/// these are view-side durations rather than a server state. Used to build the
/// mute duration submenu in the feed and community screens.
enum MuteDuration: CaseIterable {
    case day, week, month, forever

    /// The expiry instant measured from now, or nil for an indefinite mute.
    var until: Date? {
        switch self {
        case .day: return Date().addingTimeInterval(24 * 60 * 60)
        case .week: return Date().addingTimeInterval(7 * 24 * 60 * 60)
        case .month: return Date().addingTimeInterval(30 * 24 * 60 * 60)
        case .forever: return nil
        }
    }

    /// The menu item label for picking this duration.
    var menuTitle: String {
        switch self {
        case .day: return NSLocalizedString("For a day", comment: "Mute community duration")
        case .week: return NSLocalizedString("For a week", comment: "Mute community duration")
        case .month: return NSLocalizedString("For a month", comment: "Mute community duration")
        case .forever: return NSLocalizedString("Until I unmute", comment: "Mute community duration: forever")
        }
    }
}
