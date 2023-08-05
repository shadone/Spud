//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
@testable import LemmyKit

extension Comment {
    static func fake(id: Int32, post: Post, creator: Person, parent: CommentPath) -> Comment {
        .init(
            id: id,
            creator_id: creator.id,
            post_id: post.id,
            content: "hello",
            removed: false,
            published: Date(),
            updated: nil,
            deleted: false,
            ap_id: URL(string: "https://example.com/comment/1")!,
            local: true,
            path: parent.appending(id).pathString,
            distinguished: false,
            language_id: 1
        )
    }
}
