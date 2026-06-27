//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

struct CommentsBackgroundTests {
    @Test
    func commentsPresentIsAlwaysHidden() {
        for loading in [true, false] {
            for completed in [true, false] {
                #expect(
                    CommentsBackground.decide(
                        isLoadingComments: loading,
                        hasCompletedFetch: completed,
                        hasComments: true
                    ) == .hidden,
                    "loading=\(loading) completed=\(completed)"
                )
            }
        }
    }

    @Test
    func loadingWithNoCommentsShowsSkeleton() {
        #expect(
            CommentsBackground.decide(isLoadingComments: true, hasCompletedFetch: false, hasComments: false) == .skeleton
        )
        #expect(
            CommentsBackground.decide(isLoadingComments: true, hasCompletedFetch: true, hasComments: false) == .skeleton
        )
    }

    @Test
    func settledWithNoCommentsShowsEmpty() {
        #expect(
            CommentsBackground.decide(isLoadingComments: false, hasCompletedFetch: true, hasComments: false) == .empty
        )
    }

    @Test
    func initialBeforeFetchShowsSkeleton() {
        #expect(
            CommentsBackground.decide(isLoadingComments: false, hasCompletedFetch: false, hasComments: false) == .skeleton
        )
    }
}
