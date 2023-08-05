//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

struct PersonFormatter {
    static func string(totalScoreForComment value: Int64) -> String {
        if value < 1000 {
            return String(value)
        }
        return String(format: "%.1fK", Double(value) / 1000)
    }

    static func string(totalScoreForPosts value: Int64) -> String {
        if value < 1000 {
            return String(value)
        }
        return String(format: "%.1fK", Double(value) / 1000)
    }

    static func string(personCreatedDate date: Date) -> String {
        date.relativeString
    }
}
