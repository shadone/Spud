//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

/// Pure (no database, no network) coverage of the bounded k-way activity merge:
/// interleaving sorted sources by `occurredAt` descending, and clamping the
/// result to the merge frontier so an already-shown prefix never reorders when a
/// later authored page arrives.
struct ActivityMergeTests {
    // MARK: - Fixture helpers

    /// Builds a minimal `.comment` activity item at the given epoch time. The
    /// comment object is used (fewer fields than `PostListRow`) since the merge
    /// only reads `id` and `occurredAt`.
    private func item(_ id: String, at epoch: TimeInterval, act: ActivityAct = .comment) -> ActivityItem {
        let row = ActivityCommentRow(
            id: 0,
            serverCommentId: 0,
            body: "",
            score: 0,
            parentPostTitle: "",
            communityName: "",
            communityActorId: nil,
            serverPostId: nil,
            published: Date(timeIntervalSince1970: epoch)
        )
        return ActivityItem(
            id: id,
            act: act,
            occurredAt: Date(timeIntervalSince1970: epoch),
            object: .comment(row)
        )
    }

    // MARK: - Interleave

    @Test
    func merge_interleavesTwoSortedSources_byOccurredAtDescending() {
        let local = [item("l-100", at: 100), item("l-60", at: 60), item("l-20", at: 20)]
        let comments = [item("c-80", at: 80), item("c-40", at: 40)]

        let merged = ActivityMerge.merge(
            local: local,
            authoredPosts: [],
            authoredComments: comments,
            frontier: nil
        )

        #expect(merged.map(\.id) == ["l-100", "c-80", "l-60", "c-40", "l-20"])
    }

    @Test
    func merge_interleavesPostsAndComments() {
        let posts = [item("p-90", at: 90, act: .post), item("p-30", at: 30, act: .post)]
        let comments = [item("c-70", at: 70), item("c-50", at: 50)]

        let merged = ActivityMerge.merge(
            local: [],
            authoredPosts: posts,
            authoredComments: comments,
            frontier: nil
        )

        #expect(merged.map(\.id) == ["p-90", "c-70", "c-50", "p-30"])
    }

    // MARK: - Frontier clamp

    @Test
    func merge_clampsItemsOlderThanFrontier() {
        let local = [item("l-100", at: 100), item("l-60", at: 60), item("l-20", at: 20)]
        let comments = [item("c-80", at: 80), item("c-40", at: 40)]

        // Frontier at 50: only items at-or-after 50 are complete and safe to show.
        let merged = ActivityMerge.merge(
            local: local,
            authoredPosts: [],
            authoredComments: comments,
            frontier: Date(timeIntervalSince1970: 50)
        )

        #expect(merged.map(\.id) == ["l-100", "c-80", "l-60"])
    }

    @Test
    func merge_frontierAtBoundaryIsInclusive() {
        let local = [item("l-100", at: 100), item("l-50", at: 50), item("l-49", at: 49)]

        let merged = ActivityMerge.merge(
            local: local,
            authoredPosts: [],
            authoredComments: [],
            frontier: Date(timeIntervalSince1970: 50)
        )

        // The boundary item (exactly at the frontier) is kept; the one below is dropped.
        #expect(merged.map(\.id) == ["l-100", "l-50"])
    }

    @Test
    func merge_nilFrontierReturnsEverything() {
        let local = [item("l-100", at: 100), item("l-1", at: 1)]
        let comments = [item("c-50", at: 50)]

        let merged = ActivityMerge.merge(
            local: local,
            authoredPosts: [],
            authoredComments: comments,
            frontier: nil
        )

        #expect(merged.count == 3)
    }

    // MARK: - De-dup

    @Test
    func merge_dedupesByIdDefensively() {
        // Same id appearing twice (e.g. a stray duplicate) collapses to one row.
        let a = item("dup", at: 100)
        let b = item("dup", at: 100)

        let merged = ActivityMerge.merge(
            local: [a],
            authoredPosts: [],
            authoredComments: [b],
            frontier: nil
        )

        #expect(merged.count == 1)
    }

    @Test
    func merge_keepsSamePostAsBothPostedAndSaved() {
        // The same underlying post can appear as a `.post` (authored) and a
        // `.save` (local) row: different acts -> different ids -> both kept.
        let posted = item("post-post-42", at: 100, act: .post)
        let saved = item("save-post-42", at: 100, act: .save)

        let merged = ActivityMerge.merge(
            local: [saved],
            authoredPosts: [posted],
            authoredComments: [],
            frontier: nil
        )

        #expect(merged.count == 2)
    }

    // MARK: - Frontier resolution

    @Test
    func frontier_isMaxOfNonNilContributions() {
        #expect(
            ActivityMerge.frontier([
                Date(timeIntervalSince1970: 10),
                nil,
                Date(timeIntervalSince1970: 30),
            ]) == Date(timeIntervalSince1970: 30)
        )
    }

    @Test
    func frontier_allNilIsNil() {
        #expect(ActivityMerge.frontier([nil, nil]) == nil)
        #expect(ActivityMerge.frontier([]) == nil)
    }
}
