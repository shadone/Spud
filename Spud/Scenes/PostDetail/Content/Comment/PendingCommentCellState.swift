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
    /// The server comment id this pending comment is replying to, or nil for a
    /// top-level reply to the post. Lets the failed-comment Edit action
    /// re-present the composer pointed at the original target.
    var parentCommentServerId: Int64?

    init(
        clientToken: String,
        body: String,
        depth: Int,
        status: Status,
        parentCommentServerId: Int64? = nil
    ) {
        self.clientToken = clientToken
        self.body = body
        self.depth = depth
        self.status = status
        self.parentCommentServerId = parentCommentServerId
    }
}
