//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension Date {
    /// Relative age string (e.g. `"3y"`, `"5mo"`, `"2d"`) measured from
    /// `reference`, which defaults to the current wall clock.
    ///
    /// Injecting a fixed `reference` makes the output deterministic — snapshot
    /// and unit tests pin it so the string no longer depends on when the test
    /// runs. Production callers omit the argument and get the `Date()` default,
    /// so their behaviour is byte-unchanged.
    func relativeString(asOf reference: Date = Date()) -> String {
        let secs = reference.timeIntervalSince(self)
        let mins = secs / 60
        let hours = mins / 60
        let days = hours / 24
        let months = days / 30 // TODO:
        let years = months / 12

        guard secs >= 0 else {
            return "in the future"
        }

        if secs < 60 {
            return "\(secs.roundedInt)s"
        }
        if mins < 60 {
            return "\(mins.roundedInt)m"
        }
        if hours < 24 {
            return "\(hours.roundedInt)h"
        }
        if days <= 30 {
            return "\(days.roundedInt)d"
        }
        if months < 12 {
            return "\(months.roundedInt)mo"
        }
        return "\(years.roundedInt)y"
    }

    /// Relative age string measured from the current wall clock.
    ///
    /// Convenience over `relativeString(asOf:)` for the common production case.
    var relativeString: String {
        relativeString(asOf: Date())
    }
}
