//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Components.Schemas.Comment {
    static func fake(
        id: Components.Schemas.CommentID,
        post: Components.Schemas.Post,
        creator: Components.Schemas.Person,
        parent: CommentPath
    ) -> Components.Schemas.Comment {
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
