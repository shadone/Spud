//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// Coordinator-level coverage: pagination advances the frontier one page at a
/// time (never "fetch everything"), the Posts/Comments filters gate the authored
/// fetch entirely, and an authored fetch failure degrades to the local stream
/// instead of failing the whole stream.
///
/// The authored source is injected as a fake so these run without a network; the
/// local + authored-post observations come from a real in-memory `AppDatabase`.
struct ActivityCoordinatorTests {
    // MARK: - Test doubles

    /// Records every requested page and replays a fixed script of pages. Pages
    /// beyond the script report both sources exhausted. Optionally throws to
    /// simulate an offline / unreachable instance.
    private actor FakeAuthoredSource: AuthoredActivitySource {
        private let pages: [AuthoredActivityPage]
        private let shouldThrow: Bool
        private(set) var requestedPages: [Int64] = []

        init(pages: [AuthoredActivityPage], shouldThrow: Bool = false) {
            self.pages = pages
            self.shouldThrow = shouldThrow
        }

        func loadPage(_ page: Int64) async throws -> AuthoredActivityPage {
            requestedPages.append(page)
            if shouldThrow {
                throw URLError(.notConnectedToInternet)
            }
            let index = Int(page) - 1
            guard index >= 0, index < pages.count else {
                return AuthoredActivityPage(
                    comments: [],
                    oldestPostPublished: nil,
                    oldestCommentPublished: nil,
                    postsExhausted: true,
                    commentsExhausted: true
                )
            }
            return pages[index]
        }
    }

    /// Collects every emission off an `AsyncStream` so tests can assert on the
    /// latest snapshot without racing the producer.
    private actor Collector<Element: Sendable> {
        private(set) var values: [Element] = []
        func append(_ value: Element) {
            values.append(value)
        }

        var last: Element? {
            values.last
        }
    }

    // MARK: - Fixture helpers

    private func commentItem(_ id: String, at epoch: TimeInterval) -> ActivityItem {
        let row = ActivityCommentRow(
            id: 0,
            serverCommentId: Int64(id.hashValue & 0x7FFFFFFF),
            body: "body \(id)",
            score: 0,
            parentPostTitle: "",
            communityName: "",
            communityActorId: nil,
            serverPostId: nil,
            published: Date(timeIntervalSince1970: epoch)
        )
        return ActivityItem(
            id: id,
            act: .comment,
            occurredAt: Date(timeIntervalSince1970: epoch),
            object: .comment(row)
        )
    }

    private func commentPage(
        _ items: [ActivityItem],
        postsExhausted: Bool = true,
        commentsExhausted: Bool = false
    ) -> AuthoredActivityPage {
        AuthoredActivityPage(
            comments: items,
            oldestPostPublished: nil,
            oldestCommentPublished: items.map(\.occurredAt).min(),
            postsExhausted: postsExhausted,
            commentsExhausted: commentsExhausted
        )
    }

    /// Polls `predicate` until it holds or the deadline passes.
    private func waitUntil(
        timeout: Duration = .seconds(3),
        _ predicate: @Sendable () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await predicate()
    }

    // MARK: - Tests

    @Test
    func filtersWithoutPostOrComment_doNotFetchAuthored() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let source = FakeAuthoredSource(pages: [commentPage([commentItem("c-1", at: 100)])])
        let coordinator = ActivityCoordinator(
            appDatabase: appDatabase,
            personRowId: nil,
            authoredSource: source
        )

        let collector = Collector<[ActivityItem]>()
        let stream = await coordinator.activityStream(
            accountId: 1,
            filters: [.save],
            searchQuery: nil
        )
        let consume = Task { for await snapshot in stream {
            await collector.append(snapshot)
        } }
        defer { consume.cancel() }

        // Give any (incorrect) authored fetch a chance to run.
        try? await Task.sleep(for: .milliseconds(200))

        let requested = await source.requestedPages
        #expect(requested.isEmpty, "authored fetch must be skipped when neither .post nor .comment is on")
    }

    @Test
    func loadMore_advancesFrontierOnePageAtATime() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let source = FakeAuthoredSource(pages: [
            commentPage([commentItem("c-100", at: 100), commentItem("c-90", at: 90)]),
            commentPage([commentItem("c-80", at: 80), commentItem("c-70", at: 70)]),
            commentPage([], commentsExhausted: true),
        ])
        let coordinator = ActivityCoordinator(
            appDatabase: appDatabase,
            personRowId: nil,
            authoredSource: source
        )

        let collector = Collector<[ActivityItem]>()
        let stream = await coordinator.activityStream(
            accountId: 1,
            filters: [.comment],
            searchQuery: nil
        )
        let consume = Task { for await snapshot in stream {
            await collector.append(snapshot)
        } }
        defer { consume.cancel() }

        // The first page loads automatically on subscribe. Wait on the emitted
        // snapshot itself (not just loadState) since the collector drains the
        // yielded value on a separate task.
        _ = await waitUntil { await (collector.last ?? []).map(\.id) == ["c-100", "c-90"] }
        #expect(await source.requestedPages == [1], "only the first page is loaded; nothing fetched ahead")
        #expect(await (collector.last ?? []).map(\.id) == ["c-100", "c-90"])

        // loadMore advances exactly one page and extends the visible frontier.
        await coordinator.loadMore()
        _ = await waitUntil { await (collector.last ?? []).map(\.id) == ["c-100", "c-90", "c-80", "c-70"] }
        #expect(await source.requestedPages == [1, 2])
        #expect(await (collector.last ?? []).map(\.id) == ["c-100", "c-90", "c-80", "c-70"])

        // The final page reports exhaustion; the coordinator settles to .complete.
        await coordinator.loadMore()
        _ = await waitUntil { await (coordinator.loadState) == .complete }
        #expect(await source.requestedPages == [1, 2, 3])
        #expect(await coordinator.loadState == .complete)
    }

    @Test
    func loadMore_isNoOpAfterSourceExhausted() async throws {
        let appDatabase = try AppDatabase.inMemory()
        // An empty page that flags exhaustion, consistent with how the production
        // source sets `commentsExhausted: response.comments.isEmpty`.
        let source = FakeAuthoredSource(pages: [
            commentPage([], commentsExhausted: true),
        ])
        let coordinator = ActivityCoordinator(
            appDatabase: appDatabase,
            personRowId: nil,
            authoredSource: source
        )

        let stream = await coordinator.activityStream(accountId: 1, filters: [.comment], searchQuery: nil)
        let consume = Task { for await _ in stream { } }
        defer { consume.cancel() }

        _ = await waitUntil { await (coordinator.loadState) == .complete }
        // Further loadMore calls must not re-request once exhausted.
        await coordinator.loadMore()
        await coordinator.loadMore()
        #expect(await source.requestedPages == [1])
    }

    @Test
    func authoredFetchFailure_degradesToLocalStreamWithoutFailing() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try await seedSavedPost(appDatabase, title: "Saved local post")

        let source = FakeAuthoredSource(pages: [], shouldThrow: true)
        let coordinator = ActivityCoordinator(
            appDatabase: appDatabase,
            personRowId: nil,
            authoredSource: source
        )

        let collector = Collector<[ActivityItem]>()
        let stream = await coordinator.activityStream(
            accountId: accountId,
            filters: [.save, .comment],
            searchQuery: nil
        )
        let consume = Task { for await snapshot in stream {
            await collector.append(snapshot)
        } }
        defer { consume.cancel() }

        // The authored fetch throws -> degraded, but the local saved post still shows.
        let degraded = await waitUntil { await (coordinator.loadState) == .degraded }
        #expect(degraded)

        let surfacedLocal = await waitUntil {
            await (collector.last ?? []).contains { $0.act == .save }
        }
        #expect(surfacedLocal, "local items keep flowing even though the authored fetch failed")
        #expect(await source.requestedPages == [1])
    }

    // MARK: - Seeding

    /// Inserts the minimal graph for a single saved post owned by a fresh
    /// account and returns the account row id. Mirrors the raw-SQL seeding used
    /// by `ActivityObservationsTests`.
    private func seedSavedPost(_ appDatabase: AppDatabase, title: String) async throws -> Int64 {
        try await appDatabase.writer.write { db in
            try db.execute(
                sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)",
                arguments: ["https://test.instance", Date()]
            )
            let instanceId = db.lastInsertedRowID
            try db.execute(
                sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)",
                arguments: [instanceId, Date(), Date()]
            )
            let siteId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO person (siteId, personId, name, isAdmin, isBanned, isBotAccount, isDeleted, isLocal,
                                        numberOfPosts, numberOfComments, createdAt, updatedAt)
                    VALUES (?, 10, 'alice', 0, 0, 0, 0, 0, 0, 0, ?, ?)
                    """,
                arguments: [siteId, Date(), Date()]
            )
            let personId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount,
                                         isSignedOutAccountType, createdAt, updatedAt)
                    VALUES (?, 'kc-activity', 0, 0, 0, ?, ?)
                    """,
                arguments: [siteId, Date(), Date()]
            )
            let accountId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO community (accountId, communityId, name, actorId, isHidden, isLocal, isNsfw,
                                           isPostingRestrictedToMods, isRemoved, subscribedState,
                                           numberOfSubscribers, numberOfPosts, numberOfComments, createdAt, updatedAt)
                    VALUES (?, 5, 'test', 'https://test.instance/c/test', 0, 0, 0, 0, 0, 'NotSubscribed', 0, 0, 0, ?, ?)
                    """,
                arguments: [accountId, Date(), Date()]
            )
            let communityId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO post (accountId, communityId, creatorId, postId, title, originalPostUrl,
                                      score, numberOfUpvotes, numberOfDownvotes, numberOfComments,
                                      isRead, isSaved, isHidden, isRemoved, isLocked,
                                      isFeaturedCommunity, isFeaturedLocal, isDeleted, published, createdAt, updatedAt)
                    VALUES (?, ?, ?, 1001, ?, 'https://test.instance/post/1001',
                            7, 7, 0, 3, 0, 1, 0, 0, 0, 0, 0, 0, ?, ?, ?)
                    """,
                arguments: [accountId, communityId, personId, title, Date(), Date(), Date()]
            )
            return accountId
        }
    }
}
