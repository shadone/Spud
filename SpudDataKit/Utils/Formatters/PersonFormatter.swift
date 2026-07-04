//
// Copyright (c) 2023-2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// Formats person/account metadata into user-visible display strings.
public enum PersonFormatter {
    /// Relative time string describing when an account was created
    /// (e.g. "3y"), measured from `asOf` (default: the current wall clock).
    /// Backed by `Date.relativeString(asOf:)`.
    ///
    /// `asOf` is additive: production and widget callers omit it and get the
    /// `Date()` default (behaviour unchanged), while snapshot/unit tests inject
    /// a fixed reference date so the string is deterministic.
    public static func string(personCreatedDate date: Date, asOf: Date = Date()) -> String {
        date.relativeString(asOf: asOf)
    }

    /// Absolute "cake day" — the calendar date the account was created,
    /// e.g. "May 6, 2023". Shown in the profile header next to the cake symbol.
    public static func cakeDayString(personCreatedDate date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// A user-facing instance-ban status, or nil when the user is not banned.
    /// A temporary ban includes its expiry date; a permanent ban (banned with
    /// no expiry) reads simply "Banned".
    public static func banStatus(isBanned: Bool, banExpires: Date?) -> String? {
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
