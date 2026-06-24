//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudDataKit

struct OutboundContentDedupTests {
    @Test
    func noMatchWhenNoComment() async throws {
        let db = try AppDatabase.inMemory()
        let acc = try await OutboundContentMigrationTests.seedAccount(db)
        let exists = try await db.matchingServerCommentExists(
            accountId: acc, postServerId: 1, parentCommentServerId: nil, body: "hello"
        )
        #expect(exists == false)
    }
    // A positive-match test requires seeding a full post+comment authored by the
    // account; cover that in CommentImporter-backed integration once available.
    // This unit test pins the negative (most common) path and the query shape.
}
