//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
@testable import Spud

/// Minimal `PostDetailCommentRow` test factory: only `id`/`depth` matter to
/// ``ShareCardAncestry``, everything else gets a neutral placeholder value.
/// Reused by `ShareCardContentTests` (comment-builder tests need the same
/// synthetic rows).
extension PostDetailCommentRow {
    static func fixture(
        id: Int64,
        depth: Int64,
        hasCreatorName: Bool = true,
        score: Int64 = 0,
        body: String? = nil,
        published: Date? = Date(timeIntervalSince1970: 0)
    ) -> PostDetailCommentRow {
        PostDetailCommentRow(
            id: id,
            position: id,
            depth: depth,
            serverCommentId: id,
            body: body ?? "comment \(id) body",
            originalCommentUrl: "https://example.com/comment/\(id)",
            score: score,
            voteStatus: nil,
            isSaved: false,
            isRemoved: false,
            isDistinguished: false,
            isDeleted: false,
            isCreatorModerator: false,
            isCreatorAdmin: false,
            isCreatorBannedFromCommunity: false,
            isCreatorBlocked: false,
            isCreatorSiteBanned: false,
            isCreatorBot: false,
            isCreatorAccountDeleted: false,
            removedReason: nil,
            published: published,
            creatorName: hasCreatorName ? "user\(id)" : nil,
            creatorPersonId: id,
            creatorActorId: "https://example.com/u/user\(id)",
            moreChildCount: nil,
            moreParentId: nil,
            childCount: nil
        )
    }
}

@MainActor
struct ShareCardAncestryTests {
    /// A two-root forest:
    /// 1 (d1) -> 2 (d2) -> 3 (d3) -> 4 (d4) -> 5 (d5)
    /// 6 (d1) -> 7 (d2)
    private func forest() -> [PostDetailCommentRow] {
        [
            .fixture(id: 1, depth: 1),
            .fixture(id: 2, depth: 2),
            .fixture(id: 3, depth: 3),
            .fixture(id: 4, depth: 4),
            .fixture(id: 5, depth: 5),
            .fixture(id: 6, depth: 1),
            .fixture(id: 7, depth: 2),
        ]
    }

    @Test
    func deepChain_returnsEveryAncestorRootMostFirst() {
        let result = ShareCardAncestry.ancestors(of: 5, in: forest())
        #expect(result.map(\.id) == [1, 2, 3, 4])
    }

    @Test
    func midTreeStart_stopsAtItsOwnBranchRoot() {
        let result = ShareCardAncestry.ancestors(of: 3, in: forest())
        #expect(result.map(\.id) == [1, 2])
    }

    @Test
    func secondRootBranch_doesNotLeakAcrossTheFirstBranch() {
        let result = ShareCardAncestry.ancestors(of: 7, in: forest())
        #expect(result.map(\.id) == [6])
    }

    @Test
    func rootComment_hasNoAncestors() {
        #expect(ShareCardAncestry.ancestors(of: 1, in: forest()).isEmpty)
        #expect(ShareCardAncestry.ancestors(of: 6, in: forest()).isEmpty)
    }

    @Test
    func unknownElementId_returnsEmpty() {
        #expect(ShareCardAncestry.ancestors(of: 999, in: forest()).isEmpty)
    }

    @Test
    func emptyOrderedRows_returnsEmpty() {
        #expect(ShareCardAncestry.ancestors(of: 1, in: []).isEmpty)
    }
}
