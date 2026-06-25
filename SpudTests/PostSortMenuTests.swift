//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import XCTest
@testable import Spud

final class PostSortMenuTests: XCTestCase {
    func testActivesOrder() {
        XCTAssertEqual(
            PostSortMenu.actives,
            [.Active, .Hot, .New, .Old, .Controversial, .Scaled]
        )
    }

    func testTopsOrder() {
        XCTAssertEqual(
            PostSortMenu.tops,
            [
                .TopSixHour, .TopTwelveHour, .TopDay, .TopWeek, .TopMonth,
                .TopThreeMonths, .TopSixMonths, .TopNineMonths, .TopYear, .TopAll,
            ]
        )
    }

    func testCommentsOrder() {
        XCTAssertEqual(PostSortMenu.comments, [.MostComments, .NewComments])
    }

    func testAllConcatenatesGroupsInOrder() {
        XCTAssertEqual(
            PostSortMenu.all,
            PostSortMenu.actives + PostSortMenu.tops + PostSortMenu.comments
        )
        XCTAssertEqual(PostSortMenu.all.count, 18)
    }

    /// The menu (shared by the post list, the Community screen, and the Person
    /// profile) must expose exactly the sort types the Lemmy API accepts — no
    /// invented or dropped options — so it stays in lock-step with the generated
    /// `SortType` if the API gains or removes a sort.
    func testAllCoversEveryApiSortTypeExactlyOnce() {
        XCTAssertEqual(
            Set(PostSortMenu.all),
            Set(Components.Schemas.SortType.allCases),
            "Sort menu must expose exactly the API's SortType set"
        )
        XCTAssertEqual(
            PostSortMenu.all.count,
            Set(PostSortMenu.all).count,
            "No sort type should appear twice"
        )
    }
}
