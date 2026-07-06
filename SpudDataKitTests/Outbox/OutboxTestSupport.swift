//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
@testable import SpudDataKit

// MARK: - Fake performer

/// A controllable stand-in for ``OutboxNetworkPerforming`` used by outbox tests.
/// Task 9 (OutboxService tests) reuses this type directly.
actor FakeOutboxPerformer: OutboxNetworkPerforming {
    enum Outcome {
        case success
        case fail(any Error)
    }

    private var outcomeByKind: [OutboxKind: Outcome] = [:]
    private(set) var performed: [OutboxOperation] = []

    func setOutcome(_ outcome: Outcome, for kind: OutboxKind) {
        outcomeByKind[kind] = outcome
    }

    func perform(_ op: OutboxOperation) async throws {
        performed.append(op)
        if case let .fail(error) = outcomeByKind[op.kind] ?? .success {
            throw error
        }
    }
}

// MARK: - Seed helpers

/// Seeds an instance, site, and account into `appDatabase`. Returns the
/// auto-assigned `(accountId, siteId)` row ids.
@discardableResult
func seedAccountAndSite(_ appDatabase: AppDatabase) async throws -> (accountId: Int64, siteId: Int64) {
    try await appDatabase.writer.write { db -> (Int64, Int64) in
        var instance = InstanceRecord(actorId: "https://example.com")
        try instance.insert(db)
        var site = SiteRecord(instanceId: instance.id!)
        try site.insert(db)
        var account = AccountRecord(
            siteId: site.id!,
            accountKeychainId: "keychain-outbox-test",
            isSignedOutAccountType: false
        )
        try account.insert(db)
        return (account.id!, site.id!)
    }
}

/// Upserts a post via the importer (satisfying all FK constraints), then
/// patches the score / voteStatus / isSaved / isHidden columns to the
/// requested initial values. Returns the server post id as `Int64`.
///
/// The fake post always uses server id 1 (the `Post.fake` fixture is fixed).
@discardableResult
func seedPost(
    _ appDatabase: AppDatabase,
    accountId: Int64,
    siteId: Int64,
    score: Int64,
    voteStatus: Int64?,
    isSaved: Bool = false,
    isHidden: Bool = false,
    isDeleted: Bool = false
) async throws -> Int64 {
    let post = Components.Schemas.Post.fake(creator: .fake, community: .fake)
    let view = Components.Schemas.PostView.fake(post: post, creator: .fake, community: .fake)
    try await appDatabase.upsertPost(from: view, accountId: accountId, siteId: siteId)

    // Patch the initial values the importer doesn't carry from the fake view.
    let serverPostId = Int64(post.id)
    try await appDatabase.writer.write { db in
        try db.execute(
            sql: """
                UPDATE post SET score = ?, voteStatus = ?, isSaved = ?, isHidden = ?, isDeleted = ?
                WHERE postId = ? AND accountId = ?
                """,
            arguments: [score, voteStatus, isSaved, isHidden, isDeleted, serverPostId, accountId]
        )
    }
    return serverPostId
}

/// Upserts a comment via the importer (post must already be seeded via
/// `seedPost`), then patches the score / voteStatus / isSaved columns to
/// the requested initial values.
///
/// The comment is attached to the fake post (server id 1) — call `seedPost`
/// first so the foreign key constraint is satisfied.
func seedComment(
    _ appDatabase: AppDatabase,
    accountId: Int64,
    siteId: Int64,
    commentServerId: Int,
    score: Int64,
    voteStatus: Int64?,
    isSaved: Bool = false,
    isDeleted: Bool = false
) async throws {
    // Recreate the same fake post the importer needs to resolve the postId FK.
    let post = Components.Schemas.Post.fake(creator: .fake, community: .fake)
    let comment = Components.Schemas.Comment.fake(
        id: Components.Schemas.CommentID(commentServerId),
        post: post,
        creator: .fake,
        parent: .root
    )
    let view = Components.Schemas.CommentView.fake(
        comment: comment,
        creator: .fake,
        post: post,
        community: .fake,
        childCount: 0
    )
    try await appDatabase.upsertComment(from: view, accountId: accountId, siteId: siteId)

    // Patch the initial values.
    let serverCommentId = Int64(commentServerId)
    try await appDatabase.writer.write { db in
        try db.execute(
            sql: """
                UPDATE comment SET score = ?, voteStatus = ?, isSaved = ?, isDeleted = ?
                WHERE localCommentId = ?
                  AND postId IN (SELECT id FROM post WHERE accountId = ?)
                """,
            arguments: [score, voteStatus, isSaved, isDeleted, serverCommentId, accountId]
        )
    }
}

/// Seeds a community owned by `accountId` with the given server id and initial
/// subscribed state (default `.notSubscribed`). When the initial state counts as
/// followed (`.subscribed` / `.pending`), the `accountFollowedCommunity` junction
/// row is created too, so the fixture matches the invariant the importer keeps.
/// Returns the server community id.
@discardableResult
func seedCommunity(
    _ appDatabase: AppDatabase,
    accountId: Int64,
    serverCommunityId: Int64 = 1,
    subscribed: CommunitySubscribedState = .notSubscribed
) async throws -> Int64 {
    try await appDatabase.writer.write { db in
        var record = CommunityRecord(
            accountId: accountId,
            communityId: serverCommunityId,
            name: "world",
            title: "World",
            subscribedState: subscribed.rawValue
        )
        try record.insert(db)
        if subscribed.isSubscribed {
            let junction = AccountFollowedCommunityRecord(
                accountId: accountId,
                communityId: record.id!
            )
            try junction.insert(db)
        }
    }
    return serverCommunityId
}

// MARK: - Read helpers

/// Reads a community's persisted `subscribedState` text plus whether its
/// `accountFollowedCommunity` junction row is present (the two projections a
/// subscribe optimistic write / rollback must keep consistent).
func readCommunitySubscribed(
    _ appDatabase: AppDatabase,
    accountId: Int64,
    serverCommunityId: Int64
) async throws -> (state: String?, followed: Bool) {
    try await appDatabase.writer.read { db -> (String?, Bool) in
        guard let row = try CommunityRecord
            .filter(Column("accountId") == accountId)
            .filter(Column("communityId") == serverCommunityId)
            .fetchOne(db),
            let rowId = row.id
        else { return (nil, false) }
        let followed = try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM accountFollowedCommunity WHERE accountId = ? AND communityId = ?)",
            arguments: [accountId, rowId]
        ) ?? false
        return (row.subscribedState, followed)
    }
}

func readPostVote(
    _ appDatabase: AppDatabase,
    accountId: Int64,
    serverPostId: Int64
) async throws -> (score: Int64, voteStatus: Int64?) {
    try await appDatabase.writer.read { db -> (Int64, Int64?) in
        let row = try PostRecord
            .filter(Column("postId") == serverPostId)
            .filter(Column("accountId") == accountId)
            .fetchOne(db)
        return (row?.score ?? 0, row?.voteStatus)
    }
}

func readPostSaved(
    _ appDatabase: AppDatabase,
    accountId: Int64,
    serverPostId: Int64
) async throws -> Bool {
    try await appDatabase.writer.read { db -> Bool in
        let row = try PostRecord
            .filter(Column("postId") == serverPostId)
            .filter(Column("accountId") == accountId)
            .fetchOne(db)
        return row?.isSaved ?? false
    }
}

func readPostHidden(
    _ appDatabase: AppDatabase,
    accountId: Int64,
    serverPostId: Int64
) async throws -> Bool {
    try await appDatabase.writer.read { db -> Bool in
        let row = try PostRecord
            .filter(Column("postId") == serverPostId)
            .filter(Column("accountId") == accountId)
            .fetchOne(db)
        return row?.isHidden ?? false
    }
}

func readPostDeleted(
    _ appDatabase: AppDatabase,
    accountId: Int64,
    serverPostId: Int64
) async throws -> Bool {
    try await appDatabase.writer.read { db -> Bool in
        let row = try PostRecord
            .filter(Column("postId") == serverPostId)
            .filter(Column("accountId") == accountId)
            .fetchOne(db)
        return row?.isDeleted ?? false
    }
}

func readPostUnavailable(
    _ appDatabase: AppDatabase,
    accountId: Int64,
    serverPostId: Int64
) async throws -> Bool {
    try await appDatabase.writer.read { db -> Bool in
        let row = try PostRecord
            .filter(Column("postId") == serverPostId)
            .filter(Column("accountId") == accountId)
            .fetchOne(db)
        return row?.isUnavailable ?? false
    }
}

func readCommentVote(
    _ appDatabase: AppDatabase,
    accountId: Int64,
    serverCommentId: Int64
) async throws -> (score: Int64, voteStatus: Int64?) {
    try await appDatabase.writer.read { db -> (Int64, Int64?) in
        let row = try CommentRecord
            .filter(Column("localCommentId") == serverCommentId)
            .filter(sql: "postId IN (SELECT id FROM post WHERE accountId = ?)", arguments: [accountId])
            .fetchOne(db)
        return (row?.score ?? 0, row?.voteStatus)
    }
}

func readCommentDeleted(
    _ appDatabase: AppDatabase,
    accountId: Int64,
    serverCommentId: Int64
) async throws -> Bool {
    try await appDatabase.writer.read { db -> Bool in
        let row = try CommentRecord
            .filter(Column("localCommentId") == serverCommentId)
            .filter(sql: "postId IN (SELECT id FROM post WHERE accountId = ?)", arguments: [accountId])
            .fetchOne(db)
        return row?.isDeleted ?? false
    }
}

// MARK: - PostView builder

/// Builds a PostView for the fake post (server id 1) with the given vote and
/// score. Used by ReconciliationGuardTests to simulate a background refresh.
func makePostView(
    postId: Int64,
    myVote: Int32?,
    score: Int64
) -> Components.Schemas.PostView {
    let post = Components.Schemas.Post.fake(creator: .fake, community: .fake)
    var counts = Components.Schemas.PostAggregates.fake(post: post)
    counts.score = score
    var view = Components.Schemas.PostView.fake(post: post, creator: .fake, community: .fake)
    view.counts = counts
    view.my_vote = myVote
    return view
}
