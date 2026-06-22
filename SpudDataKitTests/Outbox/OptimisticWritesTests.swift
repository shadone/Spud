//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import Testing
@testable import SpudDataKit

struct OptimisticWritesTests {
    @Test
    func setPostVoteAppliesDeltaAndStatus() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let ids = try await seedAccountAndSite(appDatabase)
        let serverPostId = try await seedPost(
            appDatabase,
            accountId: ids.accountId,
            siteId: ids.siteId,
            score: 5,
            voteStatus: nil
        )

        try await appDatabase.writer.write { db in
            try OptimisticWrites.setPostVote(
                db,
                accountId: ids.accountId,
                serverPostId: serverPostId,
                voteStatus: 1,
                scoreDelta: 1
            )
        }

        let (score, vote) = try await readPostVote(appDatabase, accountId: ids.accountId, serverPostId: serverPostId)
        #expect(score == 6)
        #expect(vote == 1)
    }

    @Test
    func setPostSavedTogglesFlag() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let ids = try await seedAccountAndSite(appDatabase)
        let serverPostId = try await seedPost(
            appDatabase,
            accountId: ids.accountId,
            siteId: ids.siteId,
            score: 0,
            voteStatus: nil,
            isSaved: false
        )

        try await appDatabase.writer.write { db in
            try OptimisticWrites.setPostSaved(
                db,
                accountId: ids.accountId,
                serverPostId: serverPostId,
                isSaved: true
            )
        }

        let saved = try await readPostSaved(appDatabase, accountId: ids.accountId, serverPostId: serverPostId)
        #expect(saved == true)
    }

    @Test
    func setCommentVoteAppliesDelta() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let ids = try await seedAccountAndSite(appDatabase)
        _ = try await seedPost(
            appDatabase,
            accountId: ids.accountId,
            siteId: ids.siteId,
            score: 0,
            voteStatus: nil
        )
        let commentServerId: Int64 = 42
        try await seedComment(
            appDatabase,
            accountId: ids.accountId,
            siteId: ids.siteId,
            commentServerId: Int(commentServerId),
            score: 10,
            voteStatus: nil
        )

        try await appDatabase.writer.write { db in
            try OptimisticWrites.setCommentVote(
                db,
                accountId: ids.accountId,
                serverCommentId: commentServerId,
                voteStatus: 1,
                scoreDelta: 1
            )
        }

        let (score, vote) = try await readCommentVote(appDatabase, accountId: ids.accountId, serverCommentId: commentServerId)
        #expect(score == 11)
        #expect(vote == 1)
    }

    @Test
    func setPostHiddenTogglesFlag() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let ids = try await seedAccountAndSite(appDatabase)
        let serverPostId = try await seedPost(
            appDatabase,
            accountId: ids.accountId,
            siteId: ids.siteId,
            score: 0,
            voteStatus: nil
        )
        try await appDatabase.writer.write { db in
            try OptimisticWrites.setPostHidden(db, accountId: ids.accountId, serverPostId: serverPostId, isHidden: true)
        }
        let hidden = try await readPostHidden(appDatabase, accountId: ids.accountId, serverPostId: serverPostId)
        #expect(hidden == true)
    }
}
