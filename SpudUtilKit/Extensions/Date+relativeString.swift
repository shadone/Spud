//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension Date {
    var relativeString: String {
        let secs = -timeIntervalSinceNow
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
}
