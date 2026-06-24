//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

struct PendingCommentCellState: Equatable {
    enum Status: Equatable {
        case sending
        case failed
    }

    let clientToken: String
    let body: String
    let depth: Int
    let status: Status
}
