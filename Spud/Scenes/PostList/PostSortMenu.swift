//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit

/// The post-list sort options, grouped the way they appear in the sort menu.
/// The toolbar pull-down (`PostListViewController`) and the Quick Switch sort
/// picker share this single definition. Order within each group is the
/// display order.
enum PostSortMenu {
    static let actives: [Components.Schemas.SortType] = [
        .Active, .Hot, .New, .Old, .Controversial, .Scaled,
    ]

    static let tops: [Components.Schemas.SortType] = [
        .TopSixHour, .TopTwelveHour, .TopDay, .TopWeek, .TopMonth,
        .TopThreeMonths, .TopSixMonths, .TopNineMonths, .TopYear, .TopAll,
    ]

    static let comments: [Components.Schemas.SortType] = [
        .MostComments, .NewComments,
    ]

    /// All sorts in display order: actives, then Top, then comments.
    static var all: [Components.Schemas.SortType] {
        actives + tops + comments
    }
}
