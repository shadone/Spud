//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit

// Spud's persisted feed/comment sort vocabulary is still LemmyKit's v3-fused
// `SortType` / `CommentSortType` (the raw values are stored on `FeedRecord` and
// flow through the UI). LemmyKit's version-neutral listing endpoints instead take
// a `PostSort` + an optional `TimeRange` (post) or a `CommentSort` (comment). These
// helpers un-fuse the v3 vocabulary into the neutral pair at the LemmyService
// boundary; the neutral endpoints re-fuse it for a v3 backend and pass it through
// for v4. Migrating Spud's own sort vocabulary to the neutral types is a follow-up.

extension Lemmy.SortType {
    /// Un-fuses this v3 `SortType` into the neutral `PostSort` plus, for the
    /// time-bucketed `Top*` cases, the matching `TimeRange` window. `TopAll`
    /// maps to `.top` with no window.
    var neutralPostSort: (sort: PostSort, timeRange: TimeRange?) {
        switch self {
        case .Active: (.active, nil)
        case .Hot: (.hot, nil)
        case .New: (.new, nil)
        case .Old: (.old, nil)
        case .TopSixHour: (.top, .sixHours)
        case .TopTwelveHour: (.top, .twelveHours)
        case .TopDay: (.top, .day)
        case .TopWeek: (.top, .week)
        case .TopMonth: (.top, .month)
        case .TopYear: (.top, .year)
        case .TopAll: (.top, nil)
        case .MostComments: (.mostComments, nil)
        case .NewComments: (.newComments, nil)
        case .TopThreeMonths: (.top, .threeMonths)
        case .TopSixMonths: (.top, .sixMonths)
        case .TopNineMonths: (.top, .nineMonths)
        case .Controversial: (.controversial, nil)
        case .Scaled: (.scaled, nil)
        }
    }
}

extension Lemmy.CommentSortType {
    /// Maps this v3 `CommentSortType` onto the neutral `CommentSort` (comments have
    /// no time-bucketed variant, so this is a direct one-to-one fold).
    var neutralCommentSort: CommentSort {
        switch self {
        case .Hot: .hot
        case .Top: .top
        case .New: .new
        case .Old: .old
        case .Controversial: .controversial
        }
    }
}

extension VoteDirection {
    /// Maps LemmyKit's `LikeStatus` (the `1`/`-1`/`0` score vocabulary Spud's vote
    /// outbox carries) onto the neutral `VoteDirection` the neutral vote endpoints
    /// take.
    init(_ likeStatus: LikeStatus) {
        switch likeStatus {
        case .liked: self = .up
        case .disliked: self = .down
        case .neutral: self = .none
        }
    }
}

extension Lemmy.SearchType {
    /// Maps Spud's v3-vocabulary `SearchType` onto LemmyKit's neutral `SearchType`.
    /// v3's `.Url` (filter to link posts whose url matches) has no neutral case and
    /// folds to `.all`.
    var neutralSearchType: LemmyKit.SearchType {
        switch self {
        case .All: .all
        case .Comments: .comments
        case .Posts: .posts
        case .Communities: .communities
        case .Users: .persons
        case .Url: .all
        }
    }
}
