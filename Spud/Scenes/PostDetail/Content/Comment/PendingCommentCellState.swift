//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A pending EDIT of an existing server comment. Unlike `PendingCommentCellState`
/// (which is a whole new synthetic comment node), this overlays a new body and a
/// sending/failed indicator onto the existing comment row, preserving its
/// votes/score/badges/children. The cell renders the overridden body via the
/// normal comment path and adds the status line.
struct PendingCommentEditOverlay: Equatable {
    enum Status: Equatable {
        case sending
        case failed
    }

    /// The new (locally-edited) body to show in place of the server's body.
    let body: String
    let status: Status
    /// The outbound row's client token, so a failed edit can be retried /
    /// discarded.
    let clientToken: String
}

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
