//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import Testing
@testable import SpudDataKit

@MainActor
struct MarkPostUnavailableTests {
    @Test
    func markSetsFlagByAccountId() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)

        #expect(try await readPostUnavailable(appDatabase, accountId: accountId, serverPostId: postId) == false)

        try await appDatabase.markPostUnavailable(accountId: accountId, serverPostId: postId)

        #expect(try await readPostUnavailable(appDatabase, accountId: accountId, serverPostId: postId) == true)
    }

    @Test
    func markSetsFlagByKeychainId() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)

        try await appDatabase.markPostUnavailable(forKeychainId: "keychain-outbox-test", serverPostId: postId)

        #expect(try await readPostUnavailable(appDatabase, accountId: accountId, serverPostId: postId) == true)
    }

    @Test
    func freshPostViewImportClearsFlag() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(appDatabase)
        let postId = try await seedPost(appDatabase, accountId: accountId, siteId: siteId, score: 0, voteStatus: nil)
        try await appDatabase.markPostUnavailable(accountId: accountId, serverPostId: postId)
        #expect(try await readPostUnavailable(appDatabase, accountId: accountId, serverPostId: postId) == true)

        // A fresh authoritative PostView means the post is available again.
        let view = makePostView(postId: postId, myVote: nil, score: 0)
        try await appDatabase.upsertPost(from: view, accountId: accountId, siteId: siteId)

        #expect(try await readPostUnavailable(appDatabase, accountId: accountId, serverPostId: postId) == false)
    }
}
