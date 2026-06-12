//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

enum PersonFormatter {
    static func string(personCreatedDate date: Date) -> String {
        date.relativeString
    }

    /// Absolute "cake day" - the calendar date the account was created, e.g.
    /// "May 6, 2023". Shown in the profile header next to the cake symbol.
    static func cakeDayString(personCreatedDate date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
