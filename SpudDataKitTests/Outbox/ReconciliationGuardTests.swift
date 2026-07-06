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

    // MARK: - Post-edit (content outbox) reconcile guard

    /// While a post edit is pending (sending or failed) in the content outbox, a
    /// background `getPost`/feed refresh must NOT clobber the locally-applied
    /// title/body/url/nsfw — otherwise the un-synced edit would visibly revert.
    @Test
    func refreshDoesNotClobberPendingPostEdit() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 5, voteStatus: nil)

        // Apply the optimistic edit (what NewPostViewModel.submit does), then
        // enqueue a sending outbound post-edit row for this post.
        try await appDatabase.writer.write { db in
            try OptimisticWrites.setPostContent(
                db,
                accountId: accountId,
                serverPostId: postId,
                title: "Edited title",
                body: "Edited body",
                url: "https://example.com/edited",
                nsfw: true
            )
        }
        let token = try await appDatabase.upsertOutboundDraft(
            OutboundDraftInput(
                kind: .post, body: "Edited body", postServerId: nil, parentCommentServerId: nil,
                communityServerId: 1, title: "Edited title", url: "https://example.com/edited",
                nsfw: true, postType: 0, editPostServerId: postId
            ),
            accountId: accountId, now: 0
        )
        let rowId = try await appDatabase.writer.read { db in
            try OutboundContentRecord.filter(Column("clientToken") == token).fetchOne(db)?.id
        }
        try await appDatabase.markOutboundSending(id: #require(rowId), now: 0)

        // A background refresh re-imports the server's (pre-edit) title/body.
        let refreshView = makePostView(postId: postId, myVote: 0, score: 5)
        try await appDatabase.upsertPost(from: refreshView, accountId: accountId, siteId: siteId)

        // The optimistic edit survives the refresh.
        let (title, body, url, nsfw) = try await readPostContent(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(title == "Edited title")
        #expect(body == "Edited body")
        #expect(url == "https://example.com/edited")
        #expect(nsfw == true)
    }

    /// The outbox reconciler writes confirmed server truth by passing
    /// `respectsPendingOutbox: false`, bypassing the post-edit guard.
    @Test
    func outboxReconcileWritesServerPostContent() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 5, voteStatus: nil)

        // Apply an optimistic edit + a sending outbound edit row.
        try await appDatabase.writer.write { db in
            try OptimisticWrites.setPostContent(
                db, accountId: accountId, serverPostId: postId,
                title: "Edited title", body: "Edited body", url: nil, nsfw: false
            )
        }
        let token = try await appDatabase.upsertOutboundDraft(
            OutboundDraftInput(
                kind: .post, body: "Edited body", postServerId: nil, parentCommentServerId: nil,
                communityServerId: 1, title: "Edited title", url: nil, nsfw: false, postType: 0,
                editPostServerId: postId
            ),
            accountId: accountId, now: 0
        )
        let rowId = try await appDatabase.writer.read { db in
            try OutboundContentRecord.filter(Column("clientToken") == token).fetchOne(db)?.id
        }
        try await appDatabase.markOutboundSending(id: #require(rowId), now: 0)

        // The reconciler confirms server truth and bypasses the guard, so the
        // server's (fake) title/body are written even though an edit is pending.
        let serverView = makePostView(postId: postId, myVote: 0, score: 5)
        try await appDatabase.upsertPost(
            from: serverView, accountId: accountId, siteId: siteId, respectsPendingOutbox: false
        )

        let (title, body, _, _) = try await readPostContent(appDatabase, accountId: accountId, serverPostId: postId)
        #expect(title == "Hello world") // Post.fake's title
        #expect(body == "Hello example world") // Post.fake's body
    }

    // MARK: - Community subscribe (mutation outbox) reconcile guard

    /// A background `CommunityView` import (feed / getPost / getCommunity) must
    /// not clobber an un-synced optimistic subscribe: while the `.subscribe` op is
    /// pending, the server's stale `subscribed`/junction is skipped so the header
    /// keeps showing Pending and the Subscriptions sidebar keeps the row.
    @Test
    func communityImportDoesNotClobberPendingSubscribe() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, _) = try await seedAccountAndSite(appDatabase)
        let cid = try await seedCommunity(appDatabase, accountId: accountId, subscribed: .notSubscribed)

        // Tapping Subscribe projects the optimistic Pending state + junction row.
        try await appDatabase.enqueueOutboxOperation(
            OutboxOperation(entityType: .community, entityServerId: cid, desiredState: .subscribe(true)),
            accountId: accountId,
            now: 100
        )

        // A concurrent server import still reports the pre-follow state.
        let staleView = Components.Schemas.CommunityView.fake(community: .fake, subscribed: .NotSubscribed)
        try await appDatabase.upsertCommunity(from: staleView, accountId: accountId)

        // The optimistic Pending + junction survive the reconcile.
        let (state, followed) = try await readCommunitySubscribed(appDatabase, accountId: accountId, serverCommunityId: cid)
        #expect(state == "Pending")
        #expect(followed == true)
    }

    /// `setFollowedCommunities` (every getSite) must PRESERVE an optimistic
    /// subscribe that the server hasn't processed yet: the community is ABSENT
    /// from `my_user.follows`, but its optimistic junction row + Pending state
    /// must survive the wholesale junction rewrite.
    @Test
    func setFollowedCommunitiesAbsentKeepsPendingSubscribe() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, _) = try await seedAccountAndSite(appDatabase)
        let cid = try await seedCommunity(appDatabase, accountId: accountId, subscribed: .notSubscribed)

        try await appDatabase.enqueueOutboxOperation(
            OutboxOperation(entityType: .community, entityServerId: cid, desiredState: .subscribe(true)),
            accountId: accountId,
            now: 100
        )

        // getSite returns an empty follow list (the server hasn't caught up).
        try await appDatabase.setFollowedCommunities(accountId: accountId, follows: [])

        let (state, followed) = try await readCommunitySubscribed(appDatabase, accountId: accountId, serverCommunityId: cid)
        #expect(state == "Pending")
        #expect(followed == true)
    }

    /// `setFollowedCommunities` must NOT resurrect an optimistic unsubscribe: the
    /// community is still PRESENT in `my_user.follows` (the server hasn't processed
    /// the unfollow), but neither its junction row nor its NotSubscribed state may
    /// be brought back by the wholesale rewrite.
    @Test
    func setFollowedCommunitiesPresentDoesNotResurrectPendingUnsubscribe() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, _) = try await seedAccountAndSite(appDatabase)
        let cid = try await seedCommunity(appDatabase, accountId: accountId, subscribed: .subscribed)

        // Tapping Unsubscribe projects NotSubscribed + junction removal.
        try await appDatabase.enqueueOutboxOperation(
            OutboxOperation(entityType: .community, entityServerId: cid, desiredState: .subscribe(false)),
            accountId: accountId,
            now: 100
        )

        // getSite still lists the community as followed.
        let follow = Components.Schemas.CommunityFollowerView(community: .fake, follower: .fake)
        try await appDatabase.setFollowedCommunities(accountId: accountId, follows: [follow])

        let (state, followed) = try await readCommunitySubscribed(appDatabase, accountId: accountId, serverCommunityId: cid)
        #expect(state == "NotSubscribed")
        #expect(followed == false)
    }

    /// The outbox performer's authoritative post-send mirror bypasses the guard by
    /// passing `respectsPendingOutbox: false`, so the server's confirmed subscribed
    /// state (Subscribed) replaces the optimistic Pending.
    @Test
    func outboxReconcileWritesServerSubscribedState() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, _) = try await seedAccountAndSite(appDatabase)
        let cid = try await seedCommunity(appDatabase, accountId: accountId, subscribed: .notSubscribed)

        try await appDatabase.enqueueOutboxOperation(
            OutboxOperation(entityType: .community, entityServerId: cid, desiredState: .subscribe(true)),
            accountId: accountId,
            now: 100
        )

        // The performer confirms server truth and bypasses the guard.
        let confirmedView = Components.Schemas.CommunityView.fake(community: .fake, subscribed: .Subscribed)
        try await appDatabase.upsertCommunity(from: confirmedView, accountId: accountId, respectsPendingOutbox: false)

        let (state, followed) = try await readCommunitySubscribed(appDatabase, accountId: accountId, serverCommunityId: cid)
        #expect(state == "Subscribed")
        #expect(followed == true)
    }

    /// With no pending `.subscribe` op the guard must not over-block: a server
    /// `CommunityView` import writes the authoritative subscribed state + junction
    /// normally.
    @Test
    func communityImportWithoutPendingSubscribeImportsNormally() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, _) = try await seedAccountAndSite(appDatabase)
        let cid = try await seedCommunity(appDatabase, accountId: accountId, subscribed: .notSubscribed)

        let view = Components.Schemas.CommunityView.fake(community: .fake, subscribed: .Subscribed)
        try await appDatabase.upsertCommunity(from: view, accountId: accountId)

        let (state, followed) = try await readCommunitySubscribed(appDatabase, accountId: accountId, serverCommunityId: cid)
        #expect(state == "Subscribed")
        #expect(followed == true)
    }

    /// With no pending `.subscribe` op `setFollowedCommunities` rewrites the
    /// junction from the server snapshot as before (a community present in
    /// `follows` becomes followed).
    @Test
    func setFollowedCommunitiesWithoutPendingRewritesJunctionNormally() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, _) = try await seedAccountAndSite(appDatabase)
        let cid = try await seedCommunity(appDatabase, accountId: accountId, subscribed: .notSubscribed)

        let follow = Components.Schemas.CommunityFollowerView(community: .fake, follower: .fake)
        try await appDatabase.setFollowedCommunities(accountId: accountId, follows: [follow])

        let (_, followed) = try await readCommunitySubscribed(appDatabase, accountId: accountId, serverCommunityId: cid)
        #expect(followed == true)
    }
}

private func readPostContent(
    _ appDatabase: AppDatabase,
    accountId: Int64,
    serverPostId: Int64
) async throws -> (title: String, body: String?, url: String?, nsfw: Bool) {
    try await appDatabase.writer.read { db in
        let row = try PostRecord
            .filter(Column("postId") == serverPostId)
            .filter(Column("accountId") == accountId)
            .fetchOne(db)
        return (row?.title ?? "", row?.body, row?.url, row?.isNsfw ?? false)
    }
}
