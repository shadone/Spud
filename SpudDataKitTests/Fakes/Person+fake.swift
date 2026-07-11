//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Lemmy.Person {
    /// A fake neutral ``LemmyKit/Person``. v4-shaped: post/comment counts are
    /// flattened onto the person; admin/ban standing moved off the bare person
    /// onto ``LemmyKit/PersonView``.
    static let fake: Lemmy.Person = .init(
        id: 1,
        name: "one",
        displayName: "One",
        avatarUrl: nil,
        bannerUrl: nil,
        bio: nil,
        apId: "https://example.com/u/one",
        matrixUserId: nil,
        botAccount: false,
        deleted: false,
        local: true,
        publishedAt: Date(timeIntervalSince1970: 1_683_349_689),
        updatedAt: nil,
        postCount: 0,
        commentCount: 0
    )

    /// A fake neutral ``LemmyKit/Person`` with an overridable id/name. Neutral
    /// struct fields are `let`, so tests that need a specific id/name build a
    /// fresh value here rather than mutating `.fake`.
    static func fake(
        id: Lemmy.PersonID = 1,
        name: String = "one",
        displayName: String? = "One",
        postCount: Int64 = 0,
        commentCount: Int64 = 0
    ) -> Lemmy.Person {
        .init(
            id: Int64(id),
            name: name,
            displayName: displayName,
            avatarUrl: nil,
            bannerUrl: nil,
            bio: nil,
            apId: "https://example.com/u/\(name)",
            matrixUserId: nil,
            botAccount: false,
            deleted: false,
            local: true,
            publishedAt: Date(timeIntervalSince1970: 1_683_349_689),
            updatedAt: nil,
            postCount: postCount,
            commentCount: commentCount
        )
    }
}
