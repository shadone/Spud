//
// Copyright (c) 2021-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

struct CommentsFormatter {
    static func string(from numberOfComments: Int64) -> String {
        if numberOfComments < 1000 {
            return String(numberOfComments)
        }
        return String(format: "%.1fK", Double(numberOfComments) / 1000)
    }
}
