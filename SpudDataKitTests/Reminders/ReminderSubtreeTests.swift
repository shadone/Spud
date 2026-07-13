//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

/// Coverage for Phase 3's comment-subtree generalization of `ReminderService`:
/// `setTimeReminder`/`removeTimeReminder`/`setActivityReminder`/
/// `removeActivityReminder` all gained a `rootCommentServerId` parameter
/// (defaulted to `ReminderRecord.wholePostSentinel`, which is what
/// `ReminderServiceTests`/`ReminderServiceActivityTests`/`ReminderPollTests`
/// continue to exercise unchanged), and `pollDueActivityReminders`'s
/// `commentCountFetcher` now also carries the target's `rootCommentServerId`.
///
/// These tests focus on the NEW behavior: a whole-post reminder and a
/// comment-subtree reminder on the same post are independent rows keyed by
/// `(accountId, postServerId, rootCommentServerId, kind)`, with distinct OS
/// notification request ids, and the poll only ever touches the row whose
/// target the fetcher reports growth for. Reuses
/// `ReminderServiceTests.FakeReminderNotificationScheduler`.
struct ReminderSubtreeTests {
    private static let accountId: Int64 = 1
    private static let postServerId: Int64 = 7
    private static let rootCommentServerId: Int64 = 42
    private static let apId = "https://example.com/post/7"
    private static let commentApId = "https://example.com/comment/42"

    // MARK: - Helpers

    private func makeService(
        appDatabase: AppDatabase,
        scheduler: ReminderServiceTests.FakeReminderNotificationScheduler
    ) -> ReminderService {
        ReminderService(
            accountId: Self.accountId,
            appDatabase: appDatabase,
            scheduler: scheduler
        )
    }

    /// Inserts a single `activity` reminder directly (bypassing
    /// `setActivityReminder` so `baselineAt`/`nextCheckAt` can be pinned to
    /// exact deterministic values, mirroring `ReminderPollTests`'s
    /// `seedActivityReminder` but with a settable `rootCommentServerId`.
    @discardableResult
    private func seedActivityReminder(
        _ appDatabase: AppDatabase,
        rootCommentServerId: Int64,
        baselineCount: Int64,
        baselineAt: Date,
        nextCheckAt: Date,
        postServerId: Int64 = ReminderSubtreeTests.postServerId
    ) async throws -> Int64 {
        let record = ReminderRecord(
            accountId: Self.accountId,
            postServerId: postServerId,
            apId: rootCommentServerId == ReminderRecord.wholePostSentinel ? Self.apId : Self.commentApId,
            rootCommentServerId: rootCommentServerId,
            kind: ReminderRecord.Kind.activity.rawValue,
            nextCheckAt: nextCheckAt,
            baselineCount: baselineCount,
            baselineAt: baselineAt,
            status: ReminderRecord.Status.scheduled.rawValue,
            unseen: false,
            notificationRequestId: nil,
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )
        return try await appDatabase.upsertReminder(record)
    }

    private func storedReminder(
        _ appDatabase: AppDatabase,
        rootCommentServerId: Int64,
        kind: ReminderRecord.Kind,
        postServerId: Int64 = ReminderSubtreeTests.postServerId
    ) -> ReminderRecord? {
        appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: postServerId,
            rootCommentServerId: rootCommentServerId,
            kind: kind.rawValue
        )
    }

    // MARK: - setActivityReminder persists rootCommentServerId

    @Test
    func setActivityReminderPersistsRowWithSubtreeRootCommentServerId() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        try await service.setActivityReminder(
            postServerId: Self.postServerId,
            apId: Self.commentApId,
            baselineCount: 3,
            titleSnapshot: "A great thread",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil,
            rootCommentServerId: Self.rootCommentServerId
        )

        let stored = try #require(storedReminder(appDatabase, rootCommentServerId: Self.rootCommentServerId, kind: .activity))
        #expect(stored.rootCommentServerId == Self.rootCommentServerId)
        #expect(stored.baselineCount == 3)
        #expect(stored.apId == Self.commentApId)
    }

    // MARK: - Whole-post and subtree activity reminders coexist independently

    /// Setting a whole-post AND a subtree activity reminder on the same post
    /// persists two independent rows. Their ad-hoc fire request ids (posted by
    /// `pollDueActivityReminders` via the private `activityNotificationRequestId`
    /// helper) are distinct - `-0-` for the whole-post row, `-42-` for the
    /// subtree row - so a poll firing both never collides in Notification
    /// Center.
    @Test
    func wholePostAndSubtreeActivityRemindersCoexistWithDistinctFireRequestIds() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        try await service.setActivityReminder(
            postServerId: Self.postServerId,
            apId: Self.apId,
            baselineCount: 3,
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )
        try await service.setActivityReminder(
            postServerId: Self.postServerId,
            apId: Self.commentApId,
            baselineCount: 5,
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil,
            rootCommentServerId: Self.rootCommentServerId
        )

        let rowCount = try await appDatabase.writer.read { db in
            try ReminderRecord.fetchCount(db)
        }
        #expect(rowCount == 2)
        #expect(storedReminder(appDatabase, rootCommentServerId: ReminderRecord.wholePostSentinel, kind: .activity) != nil)
        #expect(storedReminder(appDatabase, rootCommentServerId: Self.rootCommentServerId, kind: .activity) != nil)

        // Neither row is due yet (setActivityReminder arms nextCheckAt in the
        // future) - re-seed both with a past nextCheckAt so a single poll
        // sweep processes both, then fire both by returning growth for every
        // target.
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await seedActivityReminder(
            appDatabase,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            baselineCount: 3,
            baselineAt: now.addingTimeInterval(-3600),
            nextCheckAt: now.addingTimeInterval(-60)
        )
        try await seedActivityReminder(
            appDatabase,
            rootCommentServerId: Self.rootCommentServerId,
            baselineCount: 5,
            baselineAt: now.addingTimeInterval(-3600),
            nextCheckAt: now.addingTimeInterval(-60)
        )

        await service.pollDueActivityReminders(asOf: now) { _, _ in 20 }

        let postNowCalls = await scheduler.postNowCalls
        #expect(postNowCalls.count == 2)
        let requestIds = Set(postNowCalls.map(\.requestId))
        #expect(requestIds.count == 2)
        #expect(requestIds.contains { $0.contains("-0-") })
        #expect(requestIds.contains { $0.contains("-\(Self.rootCommentServerId)-") })
    }

    // MARK: - The poll only fires the target the fetcher reports growth for

    @Test
    func pollFiresOnlyTheSubtreeReminderWhenOnlyItsTargetGrew() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await seedActivityReminder(
            appDatabase,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            baselineCount: 10,
            baselineAt: now.addingTimeInterval(-3600),
            nextCheckAt: now.addingTimeInterval(-60)
        )
        try await seedActivityReminder(
            appDatabase,
            rootCommentServerId: Self.rootCommentServerId,
            baselineCount: 10,
            baselineAt: now.addingTimeInterval(-3600),
            nextCheckAt: now.addingTimeInterval(-60)
        )

        // Fetcher only reports growth for the subtree target (7, 42); the
        // whole-post target (7, 0) reads back its unchanged baseline.
        await service.pollDueActivityReminders(asOf: now) { postServerId, rootCommentServerId in
            #expect(postServerId == Self.postServerId)
            return rootCommentServerId == Self.rootCommentServerId ? 16 : 10
        }

        let postNowCalls = await scheduler.postNowCalls
        #expect(postNowCalls.count == 1)
        #expect(postNowCalls.first?.content.body.contains("6 new replies") == true)

        let subtreeRow = try #require(storedReminder(appDatabase, rootCommentServerId: Self.rootCommentServerId, kind: .activity))
        #expect(subtreeRow.status == ReminderRecord.Status.fired.rawValue)
        #expect(subtreeRow.baselineCount == 16)

        let wholePostRow = try #require(storedReminder(appDatabase, rootCommentServerId: ReminderRecord.wholePostSentinel, kind: .activity))
        #expect(wholePostRow.status == ReminderRecord.Status.scheduled.rawValue)
        #expect(wholePostRow.baselineCount == 10)
    }

    /// Mirror of the above with the roles reversed: only the whole-post
    /// target grows, so only that row fires - the subtree row is untouched.
    @Test
    func pollFiresOnlyTheWholePostReminderWhenOnlyItsTargetGrew() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await seedActivityReminder(
            appDatabase,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            baselineCount: 10,
            baselineAt: now.addingTimeInterval(-3600),
            nextCheckAt: now.addingTimeInterval(-60)
        )
        try await seedActivityReminder(
            appDatabase,
            rootCommentServerId: Self.rootCommentServerId,
            baselineCount: 10,
            baselineAt: now.addingTimeInterval(-3600),
            nextCheckAt: now.addingTimeInterval(-60)
        )

        await service.pollDueActivityReminders(asOf: now) { _, rootCommentServerId in
            rootCommentServerId == ReminderRecord.wholePostSentinel ? 16 : 10
        }

        let postNowCalls = await scheduler.postNowCalls
        #expect(postNowCalls.count == 1)
        #expect(postNowCalls.first?.content.body.contains("6 new comments") == true)

        let wholePostRow = try #require(storedReminder(appDatabase, rootCommentServerId: ReminderRecord.wholePostSentinel, kind: .activity))
        #expect(wholePostRow.status == ReminderRecord.Status.fired.rawValue)
        #expect(wholePostRow.baselineCount == 16)

        let subtreeRow = try #require(storedReminder(appDatabase, rootCommentServerId: Self.rootCommentServerId, kind: .activity))
        #expect(subtreeRow.status == ReminderRecord.Status.scheduled.rawValue)
        #expect(subtreeRow.baselineCount == 10)
    }

    // MARK: - removeTimeReminder is scoped to rootCommentServerId

    /// Removing the subtree time reminder must not touch a whole-post time
    /// reminder on the same post - they're independent rows (and independent
    /// OS notification requests).
    @Test
    func removeTimeReminderRemovesOnlyTheSubtreeReminder() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        try await service.setTimeReminder(
            postServerId: Self.postServerId,
            apId: Self.apId,
            fireAt: Date(timeIntervalSince1970: 1_800_000_000),
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )
        try await service.setTimeReminder(
            postServerId: Self.postServerId,
            apId: Self.commentApId,
            fireAt: Date(timeIntervalSince1970: 1_800_100_000),
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil,
            rootCommentServerId: Self.rootCommentServerId
        )

        try await service.removeTimeReminder(postServerId: Self.postServerId, rootCommentServerId: Self.rootCommentServerId)

        #expect(storedReminder(appDatabase, rootCommentServerId: ReminderRecord.wholePostSentinel, kind: .time) != nil)
        #expect(storedReminder(appDatabase, rootCommentServerId: Self.rootCommentServerId, kind: .time) == nil)

        // Only the subtree reminder's OS request was cancelled - its id
        // contains the comment's server id, not the whole-post sentinel.
        let cancelCalls = await scheduler.cancelCalls
        #expect(cancelCalls.count == 1)
        #expect(cancelCalls.first?.contains("-\(Self.rootCommentServerId)-") == true)
    }

    // MARK: - Subtree activity notification body copy

    @Test
    func subtreeActivityNotificationBodyReadsNewReplies() {
        let plural = ReminderNotificationFactory.activityReminderContent(
            titleSnapshot: "A great thread",
            communityName: "news",
            instanceHost: "example.com",
            apId: Self.commentApId,
            newCount: 6,
            rootCommentServerId: Self.rootCommentServerId
        )
        #expect(plural.body == "6 new replies · c/news@example.com")

        let singular = ReminderNotificationFactory.activityReminderContent(
            titleSnapshot: "A great thread",
            communityName: "news",
            instanceHost: "example.com",
            apId: Self.commentApId,
            newCount: 1,
            rootCommentServerId: Self.rootCommentServerId
        )
        #expect(singular.body == "1 new reply · c/news@example.com")

        // Whole-post content (the default rootCommentServerId) is unchanged.
        let wholePost = ReminderNotificationFactory.activityReminderContent(
            titleSnapshot: "A great thread",
            communityName: "news",
            instanceHost: "example.com",
            apId: Self.apId,
            newCount: 6
        )
        #expect(wholePost.body == "6 new comments · c/news@example.com")
    }
}
