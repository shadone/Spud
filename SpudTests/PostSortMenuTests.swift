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
}
