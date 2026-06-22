//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

final class CommentsBackgroundTests: XCTestCase {
    func testCommentsPresentIsAlwaysHidden() {
        for loading in [true, false] {
            for completed in [true, false] {
                XCTAssertEqual(
                    CommentsBackground.decide(
                        isLoadingComments: loading,
                        hasCompletedFetch: completed,
                        hasComments: true
                    ),
                    .hidden,
                    "loading=\(loading) completed=\(completed)"
                )
            }
        }
    }

    func testLoadingWithNoCommentsShowsSkeleton() {
        XCTAssertEqual(
            CommentsBackground.decide(isLoadingComments: true, hasCompletedFetch: false, hasComments: false),
            .skeleton
        )
        XCTAssertEqual(
            CommentsBackground.decide(isLoadingComments: true, hasCompletedFetch: true, hasComments: false),
            .skeleton
        )
    }

    func testSettledWithNoCommentsShowsEmpty() {
        XCTAssertEqual(
            CommentsBackground.decide(isLoadingComments: false, hasCompletedFetch: true, hasComments: false),
            .empty
        )
    }

    func testInitialBeforeFetchShowsSkeleton() {
        XCTAssertEqual(
            CommentsBackground.decide(isLoadingComments: false, hasCompletedFetch: false, hasComments: false),
            .skeleton
        )
    }
}
