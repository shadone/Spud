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

private typealias Person = Components.Schemas.Person
private typealias Community = Components.Schemas.Community
private typealias Post = Components.Schemas.Post
private typealias PostView = Components.Schemas.PostView

/// Covers the durable offline-download marker (`post.downloadedAt`) and the
/// "Downloaded" feed's read side: the additive migration, the
/// `markPostDownloaded` write, `observeDownloadedPostListRows` (marked posts
/// only, newest download first), and `downloadedPostCountSync`.
@MainActor
struct DownloadedFeedObservationsTests {
    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    // MARK: - Seed helpers

    private func seedAccountAndSite(keychainId: String) async throws -> (accountId: Int64, siteId: Int64) {
        try await appDatabase.writer.write { db in
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
            return (account.id!, site.id!)
        }
    }

    private func postView(id: Int32, title: String) -> PostView {
        var person = Person.fake
        person.id = 7
        person.name = "alice"
        person.actor_id = "https://example.com/u/alice"

        var community = Community.fake
        community.id = 100
        community.name = "world"
        community.actor_id = "https://example.com/c/world"

        var post = Post.fake(creator: person, community: community)
        post.id = Components.Schemas.PostID(id)
        post.name = title
        post.ap_id = "https://example.com/post/\(id)"
        return PostView.fake(post: post, creator: person, community: community)
    }

    private func firstEmission(keychainId: String) async -> [PostListRow] {
        for await emission in appDatabase.observeDownloadedPostListRows(forAccountKeychainId: keychainId) {
            return emission
        }
        return []
    }

    /// Directly stamps `downloadedAt` on a post row (bypassing the "now" clock in
    /// `markPostDownloaded`) so ordering can be asserted deterministically.
    private func setDownloadedAt(_ date: Date?, serverPostId: Int64, accountId: Int64) async throws {
        try await appDatabase.writer.write { db in
            let existing = try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == serverPostId)
                .fetchOne(db)
            var record = try #require(existing)
            record.downloadedAt = date
            try record.update(db)
        }
    }

    // MARK: - Migration

    @Test
    func migrationAddsNullableDownloadedAtColumn() async throws {
        let columns = try await appDatabase.writer.read { db in
            try db.columns(in: "post")
        }
        let downloadedAt = try #require(columns.first { $0.name == "downloadedAt" })
        // Additive, no backfill: the column is nullable so legacy rows stay
        // "never downloaded" (NULL) until a fresh download stamps them.
        #expect(downloadedAt.isNotNull == false)
    }

    // MARK: - markPostDownloaded + observe

    @Test
    func markPostDownloadedSurfacesOnlyMarkedPosts() async throws {
        let (accountId, siteId) = try await seedAccountAndSite(keychainId: "kc-dl-1")

        try await appDatabase.upsertPosts(
            from: [postView(id: 1, title: "One"), postView(id: 2, title: "Two"), postView(id: 3, title: "Three")],
            accountId: accountId,
            siteId: siteId
        )

        // Before any mark, the Downloaded feed is empty.
        #expect(await firstEmission(keychainId: "kc-dl-1").isEmpty)

        try await appDatabase.markPostDownloaded(serverPostId: 1, accountId: accountId)
        try await appDatabase.markPostDownloaded(serverPostId: 3, accountId: accountId)

        let rows = await firstEmission(keychainId: "kc-dl-1")
        #expect(Set(rows.map(\.serverPostId)) == [1, 3])
        #expect(!rows.contains { $0.serverPostId == 2 }, "an unmarked post must not appear")
    }

    @Test
    func observeDownloadedPostListRowsOrdersByDownloadedAtDescending() async throws {
        let (accountId, siteId) = try await seedAccountAndSite(keychainId: "kc-dl-1")

        try await appDatabase.upsertPosts(
            from: [postView(id: 10, title: "Older download"), postView(id: 20, title: "Newer download")],
            accountId: accountId,
            siteId: siteId
        )

        // Post 20 downloaded AFTER post 10, so it must sort first.
        try await setDownloadedAt(Date(timeIntervalSince1970: 1000), serverPostId: 10, accountId: accountId)
        try await setDownloadedAt(Date(timeIntervalSince1970: 2000), serverPostId: 20, accountId: accountId)

        let rows = await firstEmission(keychainId: "kc-dl-1")
        #expect(rows.map(\.serverPostId) == [20, 10])
    }

    @Test
    func markPostDownloadedIsScopedToAccount() async throws {
        let (accountA, siteA) = try await seedAccountAndSite(keychainId: "kc-A")
        // A second account with its own cached copy of the SAME server post id.
        let accountB = try await appDatabase.writer.write { db in
            var account = AccountRecord(
                siteId: siteA,
                accountKeychainId: "kc-B",
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return account.id!
        }

        try await appDatabase.upsertPosts(from: [postView(id: 1, title: "Shared")], accountId: accountA, siteId: siteA)
        try await appDatabase.upsertPosts(from: [postView(id: 1, title: "Shared")], accountId: accountB, siteId: siteA)

        // Download it while browsing account A only.
        try await appDatabase.markPostDownloaded(serverPostId: 1, accountId: accountA)

        #expect(await firstEmission(keychainId: "kc-A").map(\.serverPostId) == [1])
        #expect(await firstEmission(keychainId: "kc-B").isEmpty, "the mark must not leak into another account's Downloaded feed")
    }

    // MARK: - Count (gating)

    @Test
    func downloadedPostCountSyncCountsOnlyMarked() async throws {
        let (accountId, siteId) = try await seedAccountAndSite(keychainId: "kc-dl-1")

        try await appDatabase.upsertPosts(
            from: [postView(id: 1, title: "One"), postView(id: 2, title: "Two")],
            accountId: accountId,
            siteId: siteId
        )

        #expect(appDatabase.downloadedPostCountSync(forAccountKeychainId: "kc-dl-1") == 0)

        try await appDatabase.markPostDownloaded(serverPostId: 1, accountId: accountId)
        #expect(appDatabase.downloadedPostCountSync(forAccountKeychainId: "kc-dl-1") == 1)

        try await appDatabase.markPostDownloaded(serverPostId: 2, accountId: accountId)
        #expect(appDatabase.downloadedPostCountSync(forAccountKeychainId: "kc-dl-1") == 2)
    }
}
