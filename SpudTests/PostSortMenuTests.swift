//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import Testing
@testable import Spud

struct PostSortMenuTests {
    @Test
    func activesOrder() {
        #expect(
            PostSortMenu.actives == [.Active, .Hot, .New, .Old, .Controversial, .Scaled]
        )
    }

    @Test
    func topsOrder() {
        #expect(
            PostSortMenu.tops == [
                .TopSixHour, .TopTwelveHour, .TopDay, .TopWeek, .TopMonth,
                .TopThreeMonths, .TopSixMonths, .TopNineMonths, .TopYear, .TopAll,
            ]
        )
    }

    @Test
    func commentsOrder() {
        #expect(PostSortMenu.comments == [.MostComments, .NewComments])
    }

    @Test
    func allConcatenatesGroupsInOrder() {
        #expect(
            PostSortMenu.all == PostSortMenu.actives + PostSortMenu.tops + PostSortMenu.comments
        )
        #expect(PostSortMenu.all.count == 18)
    }

    /// The menu (shared by the post list, the Community screen, and the Person
    /// profile) must expose exactly the sort types the Lemmy API accepts — no
    /// invented or dropped options — so it stays in lock-step with the generated
    /// `SortType` if the API gains or removes a sort.
    @Test
    func allCoversEveryApiSortTypeExactlyOnce() {
        #expect(
            Set(PostSortMenu.all) == Set(Lemmy.SortType.allCases),
            "Sort menu must expose exactly the API's SortType set"
        )
        #expect(
            PostSortMenu.all.count == Set(PostSortMenu.all).count,
            "No sort type should appear twice"
        )
    }
}
