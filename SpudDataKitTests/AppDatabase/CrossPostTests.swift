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

/// Round-trip coverage for the `postCrossPost` junction: `replaceCrossPosts`
/// (write) + `crossPostSummariesSync` (read). `AppDatabase.inMemory()` applies
/// every migration at once, which is fine here — the junction is a brand-new
/// empty table, not a backfill.
@MainActor
struct CrossPostTests {
    private let keychainId = "keychain-cross-post"

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    // MARK: - Seeding

    /// Seeds instance -> site -> account, then one post per `communityNames`
    /// entry (each in its own community, so `crossPostSummariesSync`'s
    /// community join is exercised distinctly per row). Returns the account id
    /// and the server post ids, in the same order as `communityNames`.
    private func seedAccountAndPosts(
        communityNames: [String]
    ) async throws -> (accountId: Int64, serverPostIds: [Int64]) {
        let keychainId = keychainId
        return try await appDatabase.writer.write { db -> (Int64, [Int64]) in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: false
            )
            try account.insert(db)
            var creator = PersonRecord(
                siteId: site.id!,
                personId: 1,
                name: "op",
                actorId: "https://example.com/u/op"
            )
            try creator.insert(db)

            var serverPostIds: [Int64] = []
            for (index, communityName) in communityNames.enumerated() {
                var community = CommunityRecord(
                    accountId: account.id!,
                    communityId: Int64(index + 1),
                    name: communityName,
                    actorId: "https://example.com/c/\(communityName)"
                )
                try community.insert(db)

                let serverPostId = Int64(index + 1)
                var post = PostRecord(
                    accountId: account.id!,
                    communityId: community.id!,
                    creatorId: creator.id!,
                    postId: serverPostId,
                    title: "Post in \(communityName)",
                    originalPostUrl: "https://example.com/post/\(serverPostId)",
                    score: Int64(10 * (index + 1)),
                    numberOfComments: Int64(index + 1),
                    published: Date(timeIntervalSince1970: 1_700_000_000)
                )
                try post.insert(db)
                serverPostIds.append(serverPostId)
            }
            return (account.id!, serverPostIds)
        }
    }

    // MARK: - Tests

    @Test
    func replaceThenReadReturnsCrossPostsInServerOrderWithCorrectFields() async throws {
        let seed = try await seedAccountAndPosts(communityNames: ["opened", "alpha", "beta"])
        let openedId = seed.serverPostIds[0]
        let alphaId = seed.serverPostIds[1]
        let betaId = seed.serverPostIds[2]

        // Deliberately pass beta before alpha - the server's own cross-post
        // ordering, not insertion/id order - and assert the read preserves it.
        try await appDatabase.replaceCrossPosts(
            forPostServerId: openedId,
            crossPostServerIds: [betaId, alphaId],
            forKeychainId: keychainId
        )

        let summaries = appDatabase.crossPostSummariesSync(forKeychainId: keychainId, serverPostId: openedId)

        #expect(summaries.map(\.serverPostId) == [betaId, alphaId])
        #expect(summaries.map(\.communityName) == ["beta", "alpha"])
        #expect(summaries.map(\.communityActorId) == ["https://example.com/c/beta", "https://example.com/c/alpha"])
        #expect(summaries.map(\.apId) == ["https://example.com/post/\(betaId)", "https://example.com/post/\(alphaId)"])
        #expect(summaries.map(\.score) == [30, 20])
        #expect(summaries.map(\.commentCount) == [3, 2])
    }

    @Test
    func replaceReplacesRatherThanAppending() async throws {
        let seed = try await seedAccountAndPosts(communityNames: ["opened", "alpha", "beta", "gamma"])
        let openedId = seed.serverPostIds[0]
        let alphaId = seed.serverPostIds[1]
        let betaId = seed.serverPostIds[2]
        let gammaId = seed.serverPostIds[3]

        try await appDatabase.replaceCrossPosts(
            forPostServerId: openedId,
            crossPostServerIds: [alphaId, betaId],
            forKeychainId: keychainId
        )
        #expect(
            appDatabase.crossPostSummariesSync(forKeychainId: keychainId, serverPostId: openedId).map(\.serverPostId)
                == [alphaId, betaId]
        )

        // A later fetch reports a different set (gamma replaces alpha; beta
        // stays). The junction must reflect exactly this, not the union of
        // both calls.
        try await appDatabase.replaceCrossPosts(
            forPostServerId: openedId,
            crossPostServerIds: [gammaId, betaId],
            forKeychainId: keychainId
        )

        let summaries = appDatabase.crossPostSummariesSync(forKeychainId: keychainId, serverPostId: openedId)
        #expect(summaries.map(\.serverPostId) == [gammaId, betaId], "replace must not append to the prior set")
    }

    @Test
    func replaceWithEmptySetClearsTheJunction() async throws {
        let seed = try await seedAccountAndPosts(communityNames: ["opened", "alpha"])
        let openedId = seed.serverPostIds[0]
        let alphaId = seed.serverPostIds[1]

        try await appDatabase.replaceCrossPosts(
            forPostServerId: openedId,
            crossPostServerIds: [alphaId],
            forKeychainId: keychainId
        )
        #expect(!appDatabase.crossPostSummariesSync(forKeychainId: keychainId, serverPostId: openedId).isEmpty)

        // A post that lost its cross-posts (e.g. the other side unlinked) must
        // show none, not keep serving the stale set.
        try await appDatabase.replaceCrossPosts(
            forPostServerId: openedId,
            crossPostServerIds: [],
            forKeychainId: keychainId
        )

        #expect(appDatabase.crossPostSummariesSync(forKeychainId: keychainId, serverPostId: openedId).isEmpty)
    }

    @Test
    func summariesAreEmptyForAPostWithNoCrossPosts() async throws {
        let seed = try await seedAccountAndPosts(communityNames: ["opened"])
        let openedId = seed.serverPostIds[0]

        #expect(appDatabase.crossPostSummariesSync(forKeychainId: keychainId, serverPostId: openedId).isEmpty)
    }

    @Test
    func replaceSkipsACrossPostIdThatIsNotMirrored() async throws {
        let seed = try await seedAccountAndPosts(communityNames: ["opened", "alpha"])
        let openedId = seed.serverPostIds[0]
        let alphaId = seed.serverPostIds[1]
        let unmirroredId: Int64 = 9999

        try await appDatabase.replaceCrossPosts(
            forPostServerId: openedId,
            crossPostServerIds: [alphaId, unmirroredId],
            forKeychainId: keychainId
        )

        let summaries = appDatabase.crossPostSummariesSync(forKeychainId: keychainId, serverPostId: openedId)
        #expect(summaries.map(\.serverPostId) == [alphaId], "an unmirrored cross-post id must be skipped, not crash the batch")
    }
}
