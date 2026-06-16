//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension PostInteractionSnapshot {
    /// Builds a snapshot from a feed row, deriving `instanceHost` from the
    /// community's federation actor id.
    init(postListRow row: PostListRow) {
        let instanceHost = row.communityActorId.flatMap { URL(string: $0)?.host } ?? ""
        self.init(
            titleSnapshot: row.title,
            communityName: row.communityName,
            instanceHost: instanceHost,
            thumbnailUrl: row.thumbnailUrl,
            author: row.creatorName
        )
    }
}
