//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// A small content-status indicator (removed / locked / featured / deleted)
/// shown inline in a post's metadata line. Mirrors the moderation flags the
/// post view already carries; rendered as a tinted SF Symbol in the same style
/// as the saved-bookmark badge.
struct PostStatusBadge {
    let symbolName: String
    let color: UIColor

    /// The badges to render for a post row, in display priority order. A
    /// removed-by-mod or author-deleted post is the most important signal, so
    /// it comes first; pinned/locked follow.
    static func badges(for row: PostListRow) -> [PostStatusBadge] {
        badges(
            isRemoved: row.isRemoved,
            isDeleted: row.isDeleted,
            isLocked: row.isLocked,
            isFeatured: row.isFeaturedCommunity || row.isFeaturedLocal
        )
    }

    static func badges(for row: PostDetailHeaderRow) -> [PostStatusBadge] {
        badges(
            isRemoved: row.isRemoved,
            isDeleted: row.isDeleted,
            isLocked: row.isLocked,
            isFeatured: row.isFeaturedCommunity || row.isFeaturedLocal
        )
    }

    private static func badges(
        isRemoved: Bool,
        isDeleted: Bool,
        isLocked: Bool,
        isFeatured: Bool
    ) -> [PostStatusBadge] {
        var badges: [PostStatusBadge] = []
        if isRemoved {
            badges.append(.init(symbolName: "trash.slash.fill", color: .systemRed))
        } else if isDeleted {
            badges.append(.init(symbolName: "trash.fill", color: .systemRed))
        }
        if isFeatured {
            badges.append(.init(symbolName: "pin.fill", color: .systemGreen))
        }
        if isLocked {
            badges.append(.init(symbolName: "lock.fill", color: .systemYellow))
        }
        return badges
    }
}
