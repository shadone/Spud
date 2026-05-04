//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Components.Schemas.Post {
    static func fake(
        creator: Components.Schemas.Person,
        community: Components.Schemas.Community
    ) -> Components.Schemas.Post {
        .init(
            id: 1,
            name: "Hello world",
            url: nil,
            body: "Hello example world",
            creator_id: creator.id,
            community_id: community.id,
            removed: false,
            locked: false,
            published: Date(timeIntervalSince1970: 1_685_577_784),
            updated: nil,
            deleted: false,
            nsfw: false,
            embed_title: nil,
            embed_description: nil,
            thumbnail_url: nil,
            ap_id: "https://example.com/post/1",
            local: true,
            embed_video_url: nil,
            language_id: 1,
            featured_community: false,
            featured_local: false
        )
    }
}
