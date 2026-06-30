//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Pure, side-effect-free combine + clamp at the heart of the unified activity
/// timeline. Kept separate from `ActivityCoordinator` so the bounded k-way merge
/// and the frontier arithmetic can be unit-tested without a database or network.
public enum ActivityMerge {
    /// Combines the complete local activity stream with the bounded authored
    /// post / comment sources into one reverse-chronological (`occurredAt`
    /// descending) timeline, clamped to `frontier`.
    ///
    /// - Parameters:
    ///   - local: local activity items (read / seen / saved / hidden / voted).
    ///     `observeLocalActivity` returns the *full* set, so the local source is
    ///     already complete - nothing older is pending.
    ///   - authoredPosts: authored-post items, sourced from the live person-post
    ///     observation.
    ///   - authoredComments: accumulated authored-comment items (one buffer that
    ///     grows across the loaded pages).
    ///   - frontier: the oldest `occurredAt` that is complete across every
    ///     still-paginating authored source (see ``frontier(_:)``), or nil when no
    ///     authored source constrains the merge (all exhausted, or authored
    ///     content disabled). Items older than the frontier are withheld so a
    ///     later authored page can never insert above an already-shown item.
    /// - Returns: the merged items, newest first, with anything older than
    ///   `frontier` clamped off.
    public static func merge(
        local: [ActivityItem],
        authoredPosts: [ActivityItem],
        authoredComments: [ActivityItem],
        frontier: Date?
    ) -> [ActivityItem] {
        var combined: [ActivityItem] = []
        combined.reserveCapacity(local.count + authoredPosts.count + authoredComments.count)
        combined.append(contentsOf: local)
        combined.append(contentsOf: authoredPosts)
        combined.append(contentsOf: authoredComments)

        // Defensive de-dup by stable id. Each source's ids are unique by
        // construction and never collide across acts (the act is part of the id),
        // so this only removes an accidental exact duplicate - it never merges
        // "you posted" and "you saved" for the same post (different acts produce
        // different ids, so both rows are kept, which is intended in v1).
        var seen = Set<String>()
        var deduped: [ActivityItem] = []
        deduped.reserveCapacity(combined.count)
        for item in combined where seen.insert(item.id).inserted {
            deduped.append(item)
        }

        let sorted = deduped.sorted { $0.occurredAt > $1.occurredAt }

        guard let frontier else { return sorted }
        return sorted.filter { $0.occurredAt >= frontier }
    }

    /// Resolves the merge frontier from the per-source oldest-loaded timestamps.
    ///
    /// A nil contribution means the source does not constrain the merge (disabled,
    /// exhausted, or not yet loaded). The frontier is the **maximum** of the
    /// non-nil contributions: the shallowest still-paginating source bounds how
    /// far down the merged prefix is known to be complete. Returns nil when no
    /// source constrains the merge, in which case the whole merged list is safe to
    /// show.
    public static func frontier(_ contributions: [Date?]) -> Date? {
        contributions.compactMap { $0 }.max()
    }
}
