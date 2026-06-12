//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Pure, UIKit-free filtering of a post-list snapshot against the user's
/// "hide read posts" preference.
///
/// Hiding read posts is a *client-side view concern*, mirroring how
/// ``CommentCollapseState`` filters the comment tree: the full ordered feed
/// is produced by `observePostListRows` and never mutated. This helper filters
/// that ordered list down to the rows that should currently be visible.
///
/// Two live modes are supported:
///
/// - ``Mode/live`` drops every read row from the snapshot the instant it is
///   marked read, so a post vanishes as soon as it is opened or scrolled past.
/// - ``Mode/onRefresh`` keeps read rows that were already visible when the
///   feed last refreshed, only hiding rows that were read *before* this view
///   of the feed began. The set of "already read at refresh time" ids is
///   captured by the caller and passed in as `pinnedReadIds`; those rows are
///   never re-shown, but rows read during the current session stay put until
///   the next refresh. This avoids posts disappearing out from under the user
///   mid-scroll.
public enum HideReadPostsFilter {
    /// When read posts are removed from the feed.
    public enum Mode: String, CaseIterable, Codable, Sendable {
        /// Hide read posts immediately as they become read.
        case live
        /// Only hide posts that were already read at the last refresh; posts
        /// read during the current session stay until the next refresh.
        case onRefresh
    }

    /// Filters `rows` according to `mode`.
    ///
    /// - Parameters:
    ///   - rows: the full ordered feed snapshot.
    ///   - enabled: whether hide-read is on. When `false`, `rows` is returned
    ///     unchanged.
    ///   - mode: live vs refresh-only hiding.
    ///   - pinnedReadIds: for ``Mode/onRefresh``, the server post ids that were
    ///     already read when the current feed view began. Only these are
    ///     hidden; ignored for ``Mode/live``.
    /// - Returns: the rows that should be displayed, in the original order.
    public static func filter(
        rows: [PostListRow],
        enabled: Bool,
        mode: Mode,
        pinnedReadIds: Set<Int64> = []
    ) -> [PostListRow] {
        guard enabled else { return rows }

        switch mode {
        case .live:
            return rows.filter { !$0.isRead }
        case .onRefresh:
            return rows.filter { row in
                // Hide only rows that were read at refresh time; keep rows that
                // became read during the current session so they don't vanish
                // mid-scroll.
                !(row.isRead && pinnedReadIds.contains(row.serverPostId))
            }
        }
    }

    /// The set of server post ids that are currently read in `rows`. Captured
    /// at refresh time to seed ``Mode/onRefresh`` filtering.
    public static func readIds(in rows: [PostListRow]) -> Set<Int64> {
        Set(rows.lazy.filter(\.isRead).map(\.serverPostId))
    }
}
