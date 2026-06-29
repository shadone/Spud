//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
@testable import Spud

struct CommentsBackgroundTests {
    private let offlineFailure = LoadFailure(kind: .offline, diagnostics: "test")
    private let unreachableFailure = LoadFailure(kind: .unreachable, diagnostics: "test")

    @Test
    func commentsPresentIsAlwaysHidden() {
        for loading in [true, false] {
            for completed in [true, false] {
                for error in [nil, offlineFailure] {
                    #expect(
                        CommentsBackground.decide(
                            isLoadingComments: loading,
                            hasCompletedFetch: completed,
                            hasComments: true,
                            fetchError: error
                        ) == .hidden,
                        "loading=\(loading) completed=\(completed) error=\(String(describing: error))"
                    )
                }
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

    @Test
    func failedFetchWithNoCommentsShowsFailedNotEmpty() {
        // The core regression this slice fixes: an offline fetch failure must
        // surface the truthful failed state, never the misleading "No comments
        // yet" empty state.
        #expect(
            CommentsBackground.decide(
                isLoadingComments: false,
                hasCompletedFetch: true,
                hasComments: false,
                fetchError: offlineFailure
            ) == .failed(offlineFailure)
        )
        #expect(
            CommentsBackground.decide(
                isLoadingComments: false,
                hasCompletedFetch: true,
                hasComments: false,
                fetchError: unreachableFailure
            ) == .failed(unreachableFailure)
        )
    }

    @Test
    func failedFetchBeforeAnyCompletionStillShowsFailed() {
        // The failure can land before `hasCompletedFetch` flips; it must still
        // show the failed state rather than the pre-fetch skeleton.
        #expect(
            CommentsBackground.decide(
                isLoadingComments: false,
                hasCompletedFetch: false,
                hasComments: false,
                fetchError: offlineFailure
            ) == .failed(offlineFailure)
        )
    }

    @Test
    func loadingTakesPrecedenceOverError() {
        // While a (retry) fetch is in flight, the skeleton wins over a stale
        // failure so the failed state doesn't flash behind the spinner.
        #expect(
            CommentsBackground.decide(
                isLoadingComments: true,
                hasCompletedFetch: true,
                hasComments: false,
                fetchError: offlineFailure
            ) == .skeleton
        )
    }
}
