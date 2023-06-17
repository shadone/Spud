//
// Copyright (c) 2021-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

struct UpvotesFormatter {
    static func string(from numberOfUpvotes: Int64) -> String {
        if numberOfUpvotes < 1000 {
            return String(numberOfUpvotes)
        }
        return String(format: "%.1fK", Double(numberOfUpvotes) / 1000)
    }
}
