//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Lemmy.Community {
    /// A fake neutral ``LemmyKit/Community``. v4-shaped: the subscriber/post/comment
    /// aggregates are flattened onto the community (v3's `description` maps to
    /// `sidebar`, `actor_id` to `apId`, and the plain `hidden` bool to `visibility`).
    static let fake: Lemmy.Community = .init(
        id: 1,
        name: "world",
        title: "World",
        sidebar: "Hello world community",
        apId: "https://example.com/c/world",
        iconUrl: nil,
        bannerUrl: nil,
        visibility: ._public,
        local: true,
        nsfw: false,
        postingRestrictedToMods: false,
        removed: false,
        deleted: false,
        publishedAt: Date(timeIntervalSince1970: 1_680_667_628),
        updatedAt: nil,
        subscribers: 100,
        posts: 50,
        comments: 200
    )

    /// A fake neutral ``LemmyKit/Community`` with overridable id/name/apId. Neutral
    /// struct fields are `let`, so tests that need a specific id/name/apId build a
    /// fresh value here rather than mutating `.fake`.
    static func fake(
        id: Lemmy.CommunityID = 1,
        name: String = "world",
        apId: String? = nil,
        subscribers: Int64 = 100,
        posts: Int64 = 50,
        comments: Int64 = 200
    ) -> Lemmy.Community {
        .init(
            id: Int64(id),
            name: name,
            title: "World",
            sidebar: "Hello world community",
            apId: apId ?? "https://example.com/c/\(name)",
            iconUrl: nil,
            bannerUrl: nil,
            visibility: ._public,
            local: true,
            nsfw: false,
            postingRestrictedToMods: false,
            removed: false,
            deleted: false,
            publishedAt: Date(timeIntervalSince1970: 1_680_667_628),
            updatedAt: nil,
            subscribers: subscribers,
            posts: posts,
            comments: comments
        )
    }
}
