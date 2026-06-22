//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import LemmyKit
import Testing
@testable import SpudDataKit

struct ReconciliationGuardTests {
    /// A background refresh must not clobber un-synced optimistic vote state.
    @Test
    func refreshDoesNotClobberPendingVote() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)

        // Seed post with score=5, no vote.
        let postId = try await seedPost(
            appDatabase,
            accountId: accountId,
            siteId: siteId,
            score: 5,
            voteStatus: nil
        )

        // Enqueue a vote-liked: optimistic score becomes 6, voteStatus = 1.
        try await appDatabase.enqueueOutboxOperation(
            OutboxOperation(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)),
            accountId: accountId,
            now: 100
        )

        // Simulate a background refresh that returns the old server state
        // (score=5, no vote) — the guard should preserve the optimistic state.
        let refreshView = makePostView(postId: postId, myVote: 0, score: 5)
        try await appDatabase.upsertPost(
            from: refreshView,
            accountId: accountId,
            siteId: siteId
        )

        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(score == 6)
        #expect(vote == 1)
    }

    /// When the outbox reconciler writes the confirmed server truth it bypasses
    /// the guard by passing respectsPendingOutbox: false.
    @Test
    func outboxReconcileWritesServerTruth() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)

        let postId = try await seedPost(
            appDatabase,
            accountId: accountId,
            siteId: siteId,
            score: 5,
            voteStatus: nil
        )

        // Enqueue a vote-liked: optimistic score becomes 6, voteStatus = 1.
        try await appDatabase.enqueueOutboxOperation(
            OutboxOperation(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)),
            accountId: accountId,
            now: 100
        )

        // The reconciler confirms server truth (score=99, my_vote=1) and
        // bypasses the guard so the confirmed values are written.
        let serverView = makePostView(postId: postId, myVote: 1, score: 99)
        try await appDatabase.upsertPost(
            from: serverView,
            accountId: accountId,
            siteId: siteId,
            respectsPendingOutbox: false
        )

        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(score == 99)
        #expect(vote == 1)
    }
}
