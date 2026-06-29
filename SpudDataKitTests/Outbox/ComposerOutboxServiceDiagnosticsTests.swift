//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

/// Tests that ``ComposerOutboxService`` emits structured diagnostic events at
/// every stage of the drain lifecycle. Covers the two critical paths:
///
/// - **Permanent failure** (`op.permanentPark`) — the silent discard that was
///   previously invisible in logs; row is KEPT (parked with `status = failed`),
///   unlike the mutation outbox which rolls back. The test asserts both the
///   event and the preserved row.
/// - **Dedup adoption** (`dedup.adopt`) — a comment-create whose body already
///   exists on the server is adopted (row deleted) without calling the performer.
///
/// Each test injects a fresh ``DiagnosticLogSpy`` so event assertions are
/// precise and no database I/O or OSLog side-effects occur.
@MainActor
struct ComposerOutboxServiceDiagnosticsTests {
    // MARK: - Helpers

    private func makeService(
        _ appDatabase: AppDatabase,
        _ performer: FakeComposerPerformer,
        online: Bool = true,
        accountId: Int64,
        diagnostics: DiagnosticLogSpy,
        instance: String? = "lemmy.test"
    ) -> ComposerOutboxService {
        ComposerOutboxService(
            accountId: accountId,
            appDatabase: appDatabase,
            performer: performer,
            reachability: StaticReachabilityMonitor(isOnline: online),
            now: { 1000 },
            diagnostics: diagnostics,
            instance: instance
        )
    }

    // MARK: - Tests

    /// A permanent failure must emit `op.permanentPark` with the configured
    /// instance, and the outbound row must REMAIN with `status = failed`
    /// (content is kept — unlike the mutation outbox which rolls back).
    @Test
    func permanentFailureEmitsParkEventAndKeepsRow() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try await OutboundContentMigrationTests.seedAccount(appDatabase)
        let performer = FakeComposerPerformer(mode: .throwPermanent)
        let spy = DiagnosticLogSpy()
        let service = makeService(appDatabase, performer, accountId: accountId, diagnostics: spy)

        let failures = await service.failureEvents
        let collector = Task {
            for await _ in failures {
                break
            }
        }

        let token = try await appDatabase.upsertOutboundDraft(
            OutboundDraftInput(
                kind: .comment, body: "hello", postServerId: 1,
                parentCommentServerId: nil, communityServerId: nil,
                title: nil, url: nil, nsfw: false, postType: 0
            ),
            accountId: accountId, now: 1000
        )
        try await appDatabase.markOutboundQueued(clientToken: token, now: 1000)
        await service.drainOnce()
        await collector.value

        // Row must still exist with status = failed (content kept, not rolled back).
        let rows = try await appDatabase.allOutbound(accountId: accountId)
        #expect(rows.count == 1, "permanent failure must keep the outbound row (parked)")
        #expect(rows.first?.status == OutboundStatus.failed.rawValue, "row must be parked as failed")

        // Exactly one op.permanentPark event must have been recorded.
        let parks = spy.events(matching: "op.permanentPark")
        #expect(parks.count == 1, "expected exactly one op.permanentPark event")

        let park = try #require(parks.first)
        #expect(park.category == .composerOutbox)
        #expect(park.level == .error)
        #expect(park.instance == "lemmy.test")
        #expect(park.metadata?["kind"] == "comment")

        // No success event and no rollback-style event.
        #expect(spy.events(matching: "op.permanentRollback").isEmpty, "composer must not emit rollback (mutation outbox only)")
    }

    /// A dedup adoption (comment-create body matches server) must emit
    /// `dedup.adopt` and remove the outbound row without calling the performer.
    @Test
    func dedupAdoptionEmitsAdoptEvent() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try await OutboundContentMigrationTests.seedAccount(appDatabase)
        // Seed a matching server comment so dedup triggers.
        try await ComposerOutboxServiceDiagnosticsTests.seedOwnComment(
            appDatabase, accountId: accountId, serverCommentId: 55, body: "hello"
        )

        let performer = FakeComposerPerformer(mode: .success(nil))
        let spy = DiagnosticLogSpy()
        let service = makeService(appDatabase, performer, accountId: accountId, diagnostics: spy)

        let token = try await appDatabase.upsertOutboundDraft(
            OutboundDraftInput(
                kind: .comment, body: "hello", postServerId: 1,
                parentCommentServerId: nil, communityServerId: nil,
                title: nil, url: nil, nsfw: false, postType: 0
            ),
            accountId: accountId, now: 1000
        )
        try await appDatabase.markOutboundQueued(clientToken: token, now: 1000)
        await service.drainOnce()

        // Performer must not have been called (dedup adopted the existing comment).
        #expect(await performer.calls == 0, "dedup adoption must not call performer")
        // Row must have been removed.
        #expect(try await appDatabase.allOutbound(accountId: accountId).isEmpty, "dedup adoption must delete outbound row")

        // Exactly one dedup.adopt event.
        let adopts = spy.events(matching: "dedup.adopt")
        #expect(adopts.count == 1, "expected exactly one dedup.adopt event")

        let adopt = try #require(adopts.first)
        #expect(adopt.category == .composerOutbox)
        #expect(adopt.level == .notice)
        #expect(adopt.instance == "lemmy.test")
        #expect(adopt.metadata?["kind"] == "comment")
    }

    // MARK: - Fixtures

    /// Seeds an own comment on post 1 so `matchingServerCommentExists` returns true.
    /// Matches the GRDB schema: person + community + post + comment with FK joins.
    private static func seedOwnComment(
        _ db: AppDatabase,
        accountId: Int64,
        serverCommentId: Int64,
        body: String
    ) async throws {
        let now = Date()
        try await db.writer.write { write in
            let siteId = try Int64.fetchOne(
                write, sql: "SELECT siteId FROM account WHERE id = ?", arguments: [accountId]
            )!
            // Person (the comment author == the account owner).
            try write.execute(sql: """
                INSERT INTO person
                    (siteId, personId, isAdmin, isBanned, isBotAccount, isDeleted, isLocal,
                     numberOfPosts, numberOfComments, createdAt, updatedAt)
                VALUES (?, 1, 0, 0, 0, 0, 1, 0, 0, ?, ?)
                """, arguments: [siteId, now, now])
            let personRowId = write.lastInsertedRowID
            // Point the account at this person (the join key is personId, not row id).
            try write.execute(
                sql: "UPDATE account SET personId = 1 WHERE id = ?", arguments: [accountId]
            )
            // Community (post FK).
            try write.execute(sql: """
                INSERT INTO community
                    (accountId, communityId, isHidden, isLocal, isNsfw, isPostingRestrictedToMods,
                     isRemoved, subscribedState, numberOfSubscribers, numberOfPosts,
                     numberOfComments, createdAt, updatedAt)
                VALUES (?, 1, 0, 1, 0, 0, 0, 'NotSubscribed', 0, 0, 0, ?, ?)
                """, arguments: [accountId, now, now])
            let communityRowId = write.lastInsertedRowID
            // Post (server id 1) authored by the person.
            try write.execute(sql: """
                INSERT INTO post
                    (accountId, communityId, creatorId, postId, title, originalPostUrl,
                     score, numberOfUpvotes, numberOfDownvotes, numberOfComments,
                     isRead, isSaved, isHidden, isRemoved, isLocked,
                     isFeaturedCommunity, isFeaturedLocal, isDeleted,
                     published, createdAt, updatedAt)
                VALUES (?, ?, ?, 1, 'T', 'https://example.com/post/1', 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, 0, ?, ?, ?)
                """, arguments: [accountId, communityRowId, personRowId, now, now, now])
            let postRowId = write.lastInsertedRowID
            // Comment authored by the person, with the given server id + body.
            try write.execute(sql: """
                INSERT INTO comment
                    (postId, creatorId, localCommentId, body, score, numberOfUpvotes,
                     numberOfDownvotes, published, createdAt, updatedAt, isSaved,
                     isRemoved, isDistinguished, isDeleted, isCreatorModerator,
                     isCreatorAdmin, isCreatorBannedFromCommunity, isCreatorBlocked)
                VALUES (?, ?, ?, ?, 0, 0, 0, ?, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0)
                """, arguments: [postRowId, personRowId, serverCommentId, body, now, now, now])
        }
    }
}

// MARK: - Fake performer (local to this file)

private actor FakeComposerPerformer: OutboundContentPerforming {
    enum Mode { case success(Int64?), throwTransient, throwPermanent }
    var mode: Mode
    private(set) var calls = 0

    init(mode: Mode) {
        self.mode = mode
    }

    func perform(_ record: OutboundContentRecord) async throws -> Int64? {
        calls += 1
        switch mode {
        case let .success(id): return id
        case .throwTransient: throw URLError(.notConnectedToInternet)
        case .throwPermanent: throw LemmyServiceError.requiresAuthentication
        }
    }
}
