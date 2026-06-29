//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

/// Covers the post-detail reconnect auto-retry decision: comments re-fetch only
/// on the offline -> online edge, and only when the last fetch failed. This is
/// the logic that makes the offline failed-state copy ("Spud will retry
/// automatically when you're back online") truthful.
struct CommentsReconnectRetryTests {
    @Test
    func retriesOnReconnectEdgeWhenCommentsFailed() {
        // The core behaviour: connectivity returned (offline -> online) and the
        // last comment fetch failed, so re-run the fetch.
        #expect(
            CommentsReconnectRetry.shouldRetry(isOnline: true, wasOnline: false, hasFetchError: true)
        )
    }

    @Test
    func doesNotRetryWhenCommentsLoadedFine() {
        // Connectivity returned but the comments are not in a failed state, so a
        // reconnect must not trigger a spurious re-fetch.
        #expect(
            !CommentsReconnectRetry.shouldRetry(isOnline: true, wasOnline: false, hasFetchError: false)
        )
    }

    @Test
    func doesNotRetryWithoutTheOfflineToOnlineEdge() {
        // `statusStream` replays its current value on subscribe; a "still online"
        // emission (wasOnline already true) is not an edge and must not retry,
        // even with a failed fetch — otherwise the replayed first emission would
        // fire a retry on every observation start.
        #expect(
            !CommentsReconnectRetry.shouldRetry(isOnline: true, wasOnline: true, hasFetchError: true)
        )
    }

    @Test
    func doesNotRetryWhenGoingOffline() {
        // The online -> offline transition is not a reconnect; never retry there.
        #expect(
            !CommentsReconnectRetry.shouldRetry(isOnline: false, wasOnline: true, hasFetchError: true)
        )
        #expect(
            !CommentsReconnectRetry.shouldRetry(isOnline: false, wasOnline: false, hasFetchError: true)
        )
    }
}
