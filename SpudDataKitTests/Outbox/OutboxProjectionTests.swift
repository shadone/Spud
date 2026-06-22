//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import Testing
@testable import SpudDataKit

struct OutboxProjectionTests {
    @Test
    func dbVoteStatusEncodesDistinctlyFromLikeStatus() {
        #expect(OutboxProjection.dbVoteStatus(for: .liked) == 1)
        #expect(OutboxProjection.dbVoteStatus(for: .disliked) == 0) // NOT -1
        #expect(OutboxProjection.dbVoteStatus(for: .neutral) == nil)
    }

    @Test
    func scoreDeltaCoversAllTransitions() {
        // (currentDB, desired) -> expected score delta
        #expect(OutboxProjection.voteScoreDelta(currentDB: nil, desired: .liked) == 1) // neutral -> up
        #expect(OutboxProjection.voteScoreDelta(currentDB: nil, desired: .disliked) == -1) // neutral -> down
        #expect(OutboxProjection.voteScoreDelta(currentDB: 1, desired: .neutral) == -1) // up -> neutral
        #expect(OutboxProjection.voteScoreDelta(currentDB: 0, desired: .neutral) == 1) // down -> neutral
        #expect(OutboxProjection.voteScoreDelta(currentDB: 1, desired: .disliked) == -2) // up -> down
        #expect(OutboxProjection.voteScoreDelta(currentDB: 0, desired: .liked) == 2) // down -> up
        #expect(OutboxProjection.voteScoreDelta(currentDB: 1, desired: .liked) == 0) // idempotent
    }

    @Test
    func voteStatusDecodesFromDB() {
        #expect(OutboxProjection.voteStatus(fromDB: 1).isUp)
        #expect(OutboxProjection.voteStatus(fromDB: 0).isDown)
        if case .neutral = OutboxProjection.voteStatus(fromDB: nil) {} else { Issue.record("expected neutral") }
    }
}
