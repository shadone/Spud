//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import LemmyKit
import Testing
@testable import SpudDataKit

struct PendingOperationWritesTests {
    @Test
    func enqueueAppliesOptimisticWriteAndCreatesRow() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 5, voteStatus: nil)

        try await appDatabase.enqueueOutboxOperation(
            OutboxOperation(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)),
            accountId: accountId, now: 100
        )

        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(score == 6)
        #expect(vote == 1)
        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.count == 1)
        #expect(rows[0].baseline == nil) // baseline neutral captured
        #expect(rows[0].desiredState == 1) // LikeStatus.liked
    }

    @Test
    func secondVoteCoalescesIntoOneRowPreservingBaseline() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 5, voteStatus: nil)
        func enqueue(_ s: LikeStatus, at t: Double) async throws {
            try await appDatabase.enqueueOutboxOperation(
                OutboxOperation(entityType: .post, entityServerId: postId, desiredState: .vote(s)),
                accountId: accountId, now: t
            )
        }
        try await enqueue(.liked, at: 100) // neutral -> up: score 6
        try await enqueue(.disliked, at: 200) // up -> down: score 4
        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.count == 1)
        #expect(rows[0].baseline == nil) // still the original neutral baseline
        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(score == 4)
        #expect(vote == 0)
    }

    @Test
    func toggleBackToBaselineDeletesRowAndReverts() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 5, voteStatus: nil)
        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)),
            accountId: accountId, now: 100
        )
        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .post, entityServerId: postId, desiredState: .vote(.neutral)),
            accountId: accountId, now: 200
        )
        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.isEmpty)
        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(score == 5)
        #expect(vote == nil)
    }

    @Test
    func rollbackRestoresBaseline() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 5, voteStatus: nil)
        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)),
            accountId: accountId, now: 100
        )
        let row = try #require(try await appDatabase.allOutboxOperations(accountId: accountId).first)
        try await appDatabase.rollbackOutboxOperation(row)
        let (score, vote) = try await readPostVote(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(score == 5)
        #expect(vote == nil)
        #expect(try await appDatabase.allOutboxOperations(accountId: accountId).isEmpty)
    }

    // MARK: Community subscribe

    @Test
    func enqueueSubscribeAppliesPendingAndCapturesNotSubscribedBaseline() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, _) = try await seedAccountAndSite(appDatabase)
        let cid = try await seedCommunity(appDatabase, accountId: accountId, subscribed: .notSubscribed)

        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .community, entityServerId: cid, desiredState: .subscribe(true)),
            accountId: accountId, now: 100
        )

        let (state, followed) = try await readCommunitySubscribed(appDatabase, accountId: accountId, serverCommunityId: cid)
        #expect(state == "Pending") // honest optimistic state
        #expect(followed == true)
        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows.count == 1)
        #expect(rows[0].entityType == OutboxEntityType.community.rawValue)
        #expect(rows[0].kind == OutboxKind.subscribe.rawValue)
        #expect(rows[0].baseline == 0) // notSubscribed
        #expect(rows[0].desiredState == 1) // subscribe(true)
    }

    @Test
    func enqueueUnsubscribeCapturesSubscribedBaseline() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, _) = try await seedAccountAndSite(appDatabase)
        let cid = try await seedCommunity(appDatabase, accountId: accountId, subscribed: .subscribed)

        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .community, entityServerId: cid, desiredState: .subscribe(false)),
            accountId: accountId, now: 100
        )

        let (state, followed) = try await readCommunitySubscribed(appDatabase, accountId: accountId, serverCommunityId: cid)
        #expect(state == "NotSubscribed")
        #expect(followed == false)
        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows[0].baseline == 1) // subscribed
    }

    @Test
    func enqueueUnsubscribeCapturesPendingBaseline() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, _) = try await seedAccountAndSite(appDatabase)
        let cid = try await seedCommunity(appDatabase, accountId: accountId, subscribed: .pending)

        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .community, entityServerId: cid, desiredState: .subscribe(false)),
            accountId: accountId, now: 100
        )

        let rows = try await appDatabase.allOutboxOperations(accountId: accountId)
        #expect(rows[0].baseline == 2) // pending
    }

    @Test
    func subscribeToggleBackToNotSubscribedBaselineDeletesRowAndReverts() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, _) = try await seedAccountAndSite(appDatabase)
        let cid = try await seedCommunity(appDatabase, accountId: accountId, subscribed: .notSubscribed)

        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .community, entityServerId: cid, desiredState: .subscribe(true)),
            accountId: accountId, now: 100
        )
        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .community, entityServerId: cid, desiredState: .subscribe(false)),
            accountId: accountId, now: 200
        )

        #expect(try await appDatabase.allOutboxOperations(accountId: accountId).isEmpty)
        let (state, followed) = try await readCommunitySubscribed(appDatabase, accountId: accountId, serverCommunityId: cid)
        #expect(state == "NotSubscribed")
        #expect(followed == false)
    }

    /// Toggling back to a *subscribed* baseline must restore the exact 3-valued
    /// prior state (Subscribed), NOT the 2-valued Pending the forward apply uses.
    @Test
    func subscribeToggleBackToSubscribedBaselineRestoresSubscribed() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, _) = try await seedAccountAndSite(appDatabase)
        let cid = try await seedCommunity(appDatabase, accountId: accountId, subscribed: .subscribed)

        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .community, entityServerId: cid, desiredState: .subscribe(false)),
            accountId: accountId, now: 100
        )
        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .community, entityServerId: cid, desiredState: .subscribe(true)),
            accountId: accountId, now: 200
        )

        #expect(try await appDatabase.allOutboxOperations(accountId: accountId).isEmpty)
        let (state, followed) = try await readCommunitySubscribed(appDatabase, accountId: accountId, serverCommunityId: cid)
        #expect(state == "Subscribed")
        #expect(followed == true)
    }

    @Test
    func subscribeRollbackRestoresSubscribedBaselineAndJunction() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, _) = try await seedAccountAndSite(appDatabase)
        let cid = try await seedCommunity(appDatabase, accountId: accountId, subscribed: .subscribed)

        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .community, entityServerId: cid, desiredState: .subscribe(false)),
            accountId: accountId, now: 100
        )
        // Optimistic: unsubscribed + junction removed.
        let mid = try await readCommunitySubscribed(appDatabase, accountId: accountId, serverCommunityId: cid)
        #expect(mid.followed == false)

        let row = try #require(try await appDatabase.allOutboxOperations(accountId: accountId).first)
        try await appDatabase.rollbackOutboxOperation(row)

        let (state, followed) = try await readCommunitySubscribed(appDatabase, accountId: accountId, serverCommunityId: cid)
        #expect(state == "Subscribed")
        #expect(followed == true)
        #expect(try await appDatabase.allOutboxOperations(accountId: accountId).isEmpty)
    }

    @Test
    func subscribeRollbackRestoresPendingBaselineAndJunction() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, _) = try await seedAccountAndSite(appDatabase)
        let cid = try await seedCommunity(appDatabase, accountId: accountId, subscribed: .pending)

        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .community, entityServerId: cid, desiredState: .subscribe(false)),
            accountId: accountId, now: 100
        )
        let row = try #require(try await appDatabase.allOutboxOperations(accountId: accountId).first)
        try await appDatabase.rollbackOutboxOperation(row)

        let (state, followed) = try await readCommunitySubscribed(appDatabase, accountId: accountId, serverCommunityId: cid)
        #expect(state == "Pending")
        #expect(followed == true)
    }

    @Test
    func dueFiltersByNextAttempt() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)
        try await appDatabase.enqueueOutboxOperation(
            .init(entityType: .post, entityServerId: postId, desiredState: .vote(.liked)),
            accountId: accountId, now: 100
        )
        let row = try #require(try await appDatabase.allOutboxOperations(accountId: accountId).first)
        try await appDatabase.recordOutboxAttempt(id: #require(row.id), lastError: "boom", nextAttemptAt: 500)
        #expect(try await appDatabase.dueOutboxOperations(accountId: accountId, asOf: 400).isEmpty)
        #expect(try await appDatabase.dueOutboxOperations(accountId: accountId, asOf: 600).count == 1)
    }
}
