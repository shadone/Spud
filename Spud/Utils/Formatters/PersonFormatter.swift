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

    /// A user-facing instance-ban status, or nil when the user is not banned.
    /// A temporary ban includes its expiry date; a permanent ban (banned with
    /// no expiry) reads simply "Banned".
    static func banStatus(isBanned: Bool, banExpires: Date?) -> String? {
        guard isBanned else { return nil }
        guard let banExpires else {
            return NSLocalizedString(
                "Banned",
                comment: "Profile status: the user is permanently banned from their instance"
            )
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return String(
            format: NSLocalizedString(
                "Banned · until %@",
                comment: "Profile status: temporary ban with expiry; %@ is the date"
            ),
            formatter.string(from: banExpires)
        )
    }
}
