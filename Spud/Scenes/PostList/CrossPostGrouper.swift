//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

/// Collapses feed rows that link to the same `url` (Lemmy's definition of a
/// cross-post) into one primary row plus a per-primary sibling list, so the
/// feed doesn't show the same link posted to several communities as separate
/// rows.
///
/// A pure transform over already-filtered rows — it has no knowledge of the
/// hide-read filter, muted communities, or pagination; `PostListViewController`
/// runs it after `HideReadPostsFilter` and layers its result onto the diffable
/// snapshot. See `docs/features/cross-posting.md` ("Grouping cross-posts in the
/// feed") for the product-level behavior this implements.
enum CrossPostGrouper {
    /// The outcome of grouping a page of rows.
    struct Result: Equatable {
        /// The primaries (first row seen for a grouped `url`) plus every
        /// ungroupable row (nil/empty `url`), in the original relative order of
        /// `rows`. This is what the caller should render.
        let displayed: [PostListRow]
        /// Primary `serverPostId` -> its collapsed cross-post siblings, in the
        /// order they were encountered in `rows`. Absent for a primary with no
        /// siblings (never an empty array) and absent entirely for ungroupable
        /// rows.
        let siblingsByPrimary: [Int64: [PostListRow]]

        static let empty = Result(displayed: [], siblingsByPrimary: [:])
    }

    /// Groups `rows` by normalized `url`.
    ///
    /// Rules (see `normalizedKey(for:)` for the exact normalization):
    /// - A row with a nil or blank `url` is never grouped — it always appears
    ///   in `displayed` as its own entry (text posts and no-link posts included).
    /// - The first row seen for a given normalized `url` is the **primary**: it
    ///   keeps its original position in `displayed`.
    /// - Every later row with the same normalized `url` is a **sibling**: it is
    ///   removed from `displayed` and appended, in encounter order, to
    ///   `siblingsByPrimary[primary.serverPostId]`.
    /// - `displayed` otherwise preserves the input order.
    ///
    /// This function itself is unconditional — it always groups. The caller
    /// (`PostListViewController.apply(rows:)`) is what gates grouping behind the
    /// `groupCrossPostsInFeed` preference, skipping this call entirely and using
    /// `rows` as `displayed` with an empty `siblingsByPrimary` when the
    /// preference is off.
    static func group(rows: [PostListRow]) -> Result {
        guard !rows.isEmpty else { return .empty }

        var displayed: [PostListRow] = []
        displayed.reserveCapacity(rows.count)
        var siblingsByPrimary: [Int64: [PostListRow]] = [:]
        // Normalized url -> the serverPostId of the primary already claiming it.
        var primaryByKey: [String: Int64] = [:]

        for row in rows {
            guard let key = normalizedKey(for: row.url) else {
                // Ungroupable: always its own entry, never a primary or sibling.
                displayed.append(row)
                continue
            }
            if let primaryId = primaryByKey[key] {
                siblingsByPrimary[primaryId, default: []].append(row)
            } else {
                primaryByKey[key] = row.serverPostId
                displayed.append(row)
            }
        }

        return Result(displayed: displayed, siblingsByPrimary: siblingsByPrimary)
    }

    /// Normalizes a post's `url` into a grouping key, or `nil` when the url
    /// should never be grouped (nil, blank, or whitespace-only).
    ///
    /// Deliberately conservative — normalizing too aggressively risks merging
    /// two posts that link to genuinely different things. Lemmy's own
    /// cross-post detection is exact-url; this grouper only relaxes that in
    /// the two cases below, where a false merge is essentially impossible:
    /// - **Host is lowercased** (`Example.com` and `example.com` are the same
    ///   host).
    /// - **A single trailing slash is stripped from the path**
    ///   (`/article` and `/article/` are the same page on almost every server).
    /// - **The fragment is kept as-is** — on a conventional site `#section` is
    ///   a same-page anchor, but a hash-routed single-page app encodes the
    ///   entire route after `#` (e.g. `/#/x` vs `/#/y`), so dropping it would
    ///   silently collapse two genuinely different pages into one group. A
    ///   false split (two rows instead of one) is harmless — it just shows
    ///   both; a false merge hides a real post behind the affordance, which is
    ///   the failure mode this grouper avoids everywhere else.
    /// - **The query string is kept as-is** — a `?utm_source=...` or `?id=...`
    ///   difference can legitimately point at a different resource, and this
    ///   grouper has no way to tell a tracking param from a load-bearing one.
    ///   When in doubt, this errs toward exact-match (no grouping) rather than
    ///   a false merge.
    /// - The path and query are otherwise compared byte-for-byte (case-sensitive
    ///   — paths and queries are case-sensitive per RFC 3986; only the host is
    ///   not).
    ///
    /// A `url` that isn't a parseable URL at all (shouldn't happen for a real
    /// post, whose `url` is validated at import time) falls back to the trimmed
    /// raw string, which still only matches another row byte-for-byte.
    static func normalizedKey(for url: String?) -> String? {
        guard let url else { return nil }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard var components = URLComponents(string: trimmed) else {
            return trimmed
        }
        components.host = components.host?.lowercased()
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.string ?? trimmed
    }
}
