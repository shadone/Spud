//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Lemmy.Comment {
    static func fake(
        id: Lemmy.CommentID,
        post: Lemmy.Post,
        creator: Lemmy.Person,
        parent: CommentPath
    ) -> Lemmy.Comment {
        .init(
            id: id,
            creator_id: creator.id,
            post_id: post.id,
            content: "hello",
            removed: false,
            published: Date(),
            updated: nil,
            deleted: false,
            ap_id: "https://example.com/comment/1",
            local: true,
            path: parent.appending(id).pathString,
            distinguished: false,
            language_id: 1
        )
    }
}
