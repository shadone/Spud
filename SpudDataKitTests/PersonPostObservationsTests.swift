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

private typealias Person = Lemmy.Person
private typealias Community = Lemmy.Community
private typealias Post = Lemmy.Post
private typealias PostView = Lemmy.PostView

/// Verifies `observePersonPostListRows` builds feed-parity `PostListRow`s from
/// the posts a person authored (persisted via the real `upsertPosts` importer),
/// carrying vote / saved / community / creator state and ordered per the
/// requested sort.
@MainActor
struct PersonPostObservationsTests {
    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    // MARK: - Seed helpers

    /// Seeds an instance + site + account and returns `(accountId, siteId)`.
    private func seedAccountAndSite(keychainId: String = "kc-person-1") async throws -> (accountId: Int64, siteId: Int64) {
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

    /// Builds a `PostView` authored by `person` in `community` with optional
    /// vote / saved / score state.
    ///
    /// The neutral surface has no flat `my_vote`/`saved`, and a neutral `Post`'s
    /// stored fields are `let` — so the vote/saved ride on `postActions`, and the
    /// per-post title / published / ap id / score are baked into a fresh `Post`
    /// rather than mutated onto `.fake`.
    private func postView(
        id: Int32,
        title: String,
        published: Date,
        score: Int64,
        myVote: Int32?,
        saved: Bool,
        person: Person,
        community: Community
    ) -> PostView {
        let post = Post(
            id: Int64(id),
            name: title,
            body: "Hello example world",
            url: nil,
            embedTitle: nil,
            embedDescription: nil,
            thumbnailUrl: nil,
            altText: nil,
            creatorId: person.id,
            communityId: community.id,
            apId: "https://example.com/post/\(id)",
            local: true,
            nsfw: false,
            removed: false,
            deleted: false,
            locked: false,
            featuredCommunity: false,
            featuredLocal: false,
            languageId: 1,
            publishedAt: published,
            updatedAt: nil,
            newestCommentTimeAt: published,
            score: score,
            upvotes: 1,
            downvotes: 0,
            comments: 0
        )
        let vote = VoteDirection.fromV3Score(myVote.map(Int.init))
        let postActions = PostActions(
            savedAt: saved ? Date() : nil,
            votedAt: vote == .none ? nil : Date(),
            voteIsUpvote: vote.v4IsUpvote
        )
        return PostView.fake(
            post: post,
            creator: person,
            community: community,
            postActions: postActions
        )
    }

    // MARK: - Tests

    @Test
    func observePersonPostListRows_buildsFeedParityRows() async throws {
        let (accountId, siteId) = try await seedAccountAndSite()

        let person = Person.fake(id: 7, name: "alice")

        let communityA = Community.fake(id: 100, name: "world")
        let communityB = Community.fake(id: 200, name: "news", apId: "https://lemmy.world/c/news")

        // Two posts authored by alice. The first is upvoted, the second saved.
        let upvoted = postView(
            id: 1001, title: "Upvoted post",
            published: Date(timeIntervalSince1970: 2000),
            score: 42, myVote: 1, saved: false,
            person: person, community: communityA
        )
        let savedPost = postView(
            id: 1002, title: "Saved post",
            published: Date(timeIntervalSince1970: 1000),
            score: 5, myVote: nil, saved: true,
            person: person, community: communityB
        )

        try await appDatabase.upsertPosts(
            from: [upvoted, savedPost],
            accountId: accountId,
            siteId: siteId
        )

        let personRowId = try #require(
            appDatabase.personRowIdSync(forKeychainId: "kc-person-1", personId: 7)
        )

        var rows: [PostListRow] = []
        for await emission in appDatabase.observePersonPostListRows(
            personRowId: personRowId,
            accountId: accountId,
            sort: .New
        ) {
            rows = emission
            break
        }

        #expect(rows.count == 2)

        let upRow = try #require(rows.first { $0.title == "Upvoted post" })
        #expect(upRow.communityName == "world")
        #expect(upRow.creatorActorId == "https://example.com/u/alice")
        #expect(upRow.score == 42)
        #expect(upRow.voteStatus == 1)
        #expect(upRow.isSaved == false)

        let savedRow = try #require(rows.first { $0.title == "Saved post" })
        #expect(savedRow.communityName == "news")
        #expect(savedRow.communityActorId == "https://lemmy.world/c/news")
        #expect(savedRow.score == 5)
        #expect(savedRow.voteStatus == nil)
        #expect(savedRow.isSaved == true)
    }

    @Test
    func observePersonPostListRows_ordersBySort() async throws {
        let (accountId, siteId) = try await seedAccountAndSite()

        let person = Person.fake(id: 7, name: "alice")

        let community = Community.fake

        // newer = higher published, but lower score; older = lower published,
        // higher score — so New and Top order the two differently.
        let newer = postView(
            id: 1, title: "Newer",
            published: Date(timeIntervalSince1970: 5000),
            score: 1, myVote: nil, saved: false,
            person: person, community: community
        )
        let older = postView(
            id: 2, title: "Older",
            published: Date(timeIntervalSince1970: 1000),
            score: 99, myVote: nil, saved: false,
            person: person, community: community
        )

        try await appDatabase.upsertPosts(
            from: [newer, older],
            accountId: accountId,
            siteId: siteId
        )

        let personRowId = try #require(
            appDatabase.personRowIdSync(forKeychainId: "kc-person-1", personId: 7)
        )

        func firstEmission(sort: Lemmy.SortType) async -> [PostListRow] {
            for await emission in appDatabase.observePersonPostListRows(
                personRowId: personRowId,
                accountId: accountId,
                sort: sort
            ) {
                return emission
            }
            return []
        }

        let newRows = await firstEmission(sort: .New)
        #expect(newRows.map(\.title) == ["Newer", "Older"])

        let oldRows = await firstEmission(sort: .Old)
        #expect(oldRows.map(\.title) == ["Older", "Newer"])

        let topRows = await firstEmission(sort: .TopAll)
        #expect(topRows.map(\.title) == ["Older", "Newer"], "Top sorts by score DESC")
    }
}
