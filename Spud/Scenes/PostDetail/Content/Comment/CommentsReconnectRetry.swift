//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

/// Decides whether a connectivity change should auto-retry the comment fetch.
///
/// This is what makes the offline failed-state copy ("Spud will retry
/// automatically when you're back online") true: when connectivity returns and
/// the last comment fetch failed, the post-detail screen re-fetches without the
/// user tapping Retry. Mirrors the feed's reconnect retry in
/// `PostListViewController`.
///
/// Extracted as a pure predicate (like ``CommentsBackground``) so the
/// offline -> online edge and the failed-state guard are unit-testable without
/// the view-controller lifecycle.
enum CommentsReconnectRetry {
    /// Whether to re-run the comment fetch in response to a reachability change.
    ///
    /// Fires only on the offline -> online edge (`isOnline && !wasOnline`) and
    /// only when the last fetch failed (`fetchError != nil`). The `wasOnline`
    /// guard suppresses the `statusStream` replay-on-subscribe emission (it
    /// re-yields the current value, which is not an edge). The `fetchError`
    /// guard limits the retry to one per reconnect: a successful retry clears
    /// the error, and a non-network failure (e.g. malformed response) that fails
    /// again on retry still only re-fires on the *next* reconnect, never looping.
    ///
    /// - Parameters:
    ///   - isOnline: The new reachability value emitted by the stream.
    ///   - wasOnline: The previous reachability value (the stream's prior emit).
    ///   - hasFetchError: Whether the most recent comment fetch failed.
    static func shouldRetry(isOnline: Bool, wasOnline: Bool, hasFetchError: Bool) -> Bool {
        isOnline && !wasOnline && hasFetchError
    }
}
