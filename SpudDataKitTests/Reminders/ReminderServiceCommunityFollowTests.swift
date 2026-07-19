//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import Testing
@testable import SpudDataKit

/// Coverage for `ReminderService.setCommunityFollow`/`removeCommunityFollow`/
/// `pollDueCommunityFollows` - the "notify me about new posts in this
/// community" follow (Task 2). Mirrors `ReminderServiceActivityTests` +
/// `ReminderPollTests` for the `communityPosts` kind, which reuses the
/// post-centric `reminder` columns (see `ReminderRecord`'s column-reuse doc
/// comment): `postServerId` is the community's server id, `apId` is the
/// community's actorId, and `baselineAt` is the watermark (newest post
/// `published` seen). Reuses the `FakeReminderNotificationScheduler` declared
/// in `ReminderServiceTests`.
struct ReminderServiceCommunityFollowTests {
    private static let accountId: Int64 = 1
    private static let communityServerId: Int64 = 42
    private static let communityActorId = "https://example.com/c/news"
    private static let expectedRequestId = "reminder-1-42-0-communityPosts"

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

    /// Inserts a single `communityPosts` follow directly (bypassing
    /// `setCommunityFollow` so `baselineAt`/`nextCheckAt` can be pinned to
    /// exact deterministic values rather than the wall clock) - mirrors
    /// `ReminderPollTests.seedActivityReminder`.
    @discardableResult
    private func seedCommunityFollow(
        _ appDatabase: AppDatabase,
        baselineAt: Date,
        nextCheckAt: Date,
        status: ReminderRecord.Status = .scheduled,
        communityServerId: Int64 = ReminderServiceCommunityFollowTests.communityServerId
    ) async throws -> Int64 {
        let record = ReminderRecord(
            accountId: Self.accountId,
            postServerId: communityServerId,
            apId: Self.communityActorId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.communityPosts.rawValue,
            nextCheckAt: nextCheckAt,
            baselineCount: nil,
            baselineAt: baselineAt,
            status: status.rawValue,
            unseen: false,
            notificationRequestId: nil,
            titleSnapshot: "News",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )
        return try await appDatabase.upsertReminder(record)
    }

    private func storedFollow(
        _ appDatabase: AppDatabase,
        communityServerId: Int64 = ReminderServiceCommunityFollowTests.communityServerId
    ) throws -> ReminderRecord {
        try #require(appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: communityServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.communityPosts.rawValue
        ))
    }

    // MARK: - setCommunityFollow

    @Test
    func setPersistsFollowRow() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let before = Date()
        try await service.setCommunityFollow(
            communityServerId: Self.communityServerId,
            communityActorId: Self.communityActorId,
            name: "news",
            title: "News",
            instanceHost: "example.com",
            iconUrl: "https://example.com/icon.png"
        )

        let stored = try storedFollow(appDatabase)
        #expect(stored.kind == ReminderRecord.Kind.communityPosts.rawValue)
        #expect(stored.postServerId == Self.communityServerId)
        #expect(stored.apId == Self.communityActorId)
        #expect(stored.titleSnapshot == "News")
        #expect(stored.communityName == "news")
        #expect(stored.instanceHost == "example.com")
        #expect(stored.thumbnailUrl == "https://example.com/icon.png")
        #expect(stored.baselineCount == nil)
        #expect(stored.fireAt == nil)
        #expect(stored.status == ReminderRecord.Status.scheduled.rawValue)
        #expect(stored.rootCommentServerId == ReminderRecord.wholePostSentinel)

        // baselineAt is the watermark, set to "now" at follow-time - GRDB
        // round-trips `Date` through ISO-8601 text (see the project's GRDB
        // date-storage convention), which can lose sub-second precision, so
        // compare with a tolerance (mirrors `ReminderServiceActivityTests`).
        let baselineAt = try #require(stored.baselineAt)
        #expect(abs(baselineAt.timeIntervalSince1970 - before.timeIntervalSince1970) < 2)

        let nextCheckAt = try #require(stored.nextCheckAt)
        let expectedNextCheckAt = baselineAt.addingTimeInterval(CommunityFollowRule.pollInterval)
        #expect(abs(nextCheckAt.timeIntervalSince1970 - expectedNextCheckAt.timeIntervalSince1970) < 1)
    }

    /// A second `setCommunityFollow` for the same community replaces the row
    /// (not a duplicate) - mirrors
    /// `secondSetActivityReminderForSamePostReplacesRowAndRebaselines`.
    @Test
    func setIsIdempotentPerCommunity() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        try await service.setCommunityFollow(
            communityServerId: Self.communityServerId,
            communityActorId: Self.communityActorId,
            name: "news",
            title: "Original title",
            instanceHost: "example.com",
            iconUrl: nil
        )
        try await service.setCommunityFollow(
            communityServerId: Self.communityServerId,
            communityActorId: Self.communityActorId,
            name: "news",
            title: "Updated title",
            instanceHost: "example.com",
            iconUrl: nil
        )

        let rowCount = try await appDatabase.writer.read { db in
            try ReminderRecord.fetchCount(db)
        }
        #expect(rowCount == 1)

        let stored = try storedFollow(appDatabase)
        #expect(stored.titleSnapshot == "Updated title")
    }

    // MARK: - removeCommunityFollow

    @Test
    func removeDeletesRowWithoutCancel() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        try await service.setCommunityFollow(
            communityServerId: Self.communityServerId,
            communityActorId: Self.communityActorId,
            name: "news",
            title: "News",
            instanceHost: "example.com",
            iconUrl: nil
        )

        try await service.removeCommunityFollow(communityServerId: Self.communityServerId)

        let stored = appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: Self.communityServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.communityPosts.rawValue
        )
        #expect(stored == nil)

        // Community follows never persist a notificationRequestId - there's
        // no OS request to cancel.
        let cancelCalls = await scheduler.cancelCalls
        #expect(cancelCalls.isEmpty)
    }

    /// A community follow on id 42 and an activity reminder on post 42
    /// coexist and remove independently - `kind` disambiguates the shared
    /// `postServerId` column.
    @Test
    func noCrosstalkWithActivityOnSameNumericId() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        try await service.setCommunityFollow(
            communityServerId: Self.communityServerId,
            communityActorId: Self.communityActorId,
            name: "news",
            title: "News",
            instanceHost: "example.com",
            iconUrl: nil
        )
        try await service.setActivityReminder(
            postServerId: Self.communityServerId,
            apId: "https://example.com/post/42",
            baselineCount: 3,
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )

        try await service.removeCommunityFollow(communityServerId: Self.communityServerId)

        let follow = appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: Self.communityServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.communityPosts.rawValue
        )
        #expect(follow == nil)

        let activity = appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: Self.communityServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.activity.rawValue
        )
        #expect(activity != nil)

        try await service.removeActivityReminder(postServerId: Self.communityServerId)
        let activityAfterRemove = appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: Self.communityServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.activity.rawValue
        )
        #expect(activityAfterRemove == nil)
    }

    // MARK: - pollDueCommunityFollows

    @Test
    func pollFiresOnNewPostsAndRearmsWatermark() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let watermark = now.addingTimeInterval(-3600)
        let id = try await seedCommunityFollow(
            appDatabase,
            baselineAt: watermark,
            nextCheckAt: now.addingTimeInterval(-60)
        )

        let newest = now.addingTimeInterval(-100)
        let dates = [
            watermark.addingTimeInterval(600),
            watermark.addingTimeInterval(1200),
            newest,
        ]
        await service.pollDueCommunityFollows(asOf: now, postDatesFetcher: { _, _ in dates })

        let postNowCalls = await scheduler.postNowCalls
        #expect(postNowCalls.count == 1)
        let call = try #require(postNowCalls.first)
        #expect(call.requestId == Self.expectedRequestId)
        #expect(call.content.body.contains("3 new posts"))

        let stored = try storedFollow(appDatabase)
        #expect(stored.id == id)
        #expect(stored.status == ReminderRecord.Status.fired.rawValue)
        #expect(stored.unseen == true)

        let baselineAt = try #require(stored.baselineAt)
        #expect(abs(baselineAt.timeIntervalSince1970 - newest.timeIntervalSince1970) < 1)

        let nextCheckAt = try #require(stored.nextCheckAt)
        let expectedNextCheckAt = now.addingTimeInterval(CommunityFollowRule.pollInterval)
        #expect(abs(nextCheckAt.timeIntervalSince1970 - expectedNextCheckAt.timeIntervalSince1970) < 1)
    }

    @Test
    func pollNoFireOnNoNewPosts() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let watermark = now.addingTimeInterval(-3600)
        try await seedCommunityFollow(
            appDatabase,
            baselineAt: watermark,
            nextCheckAt: now.addingTimeInterval(-60)
        )

        // All dates are at or before the watermark - nothing new.
        let dates = [watermark.addingTimeInterval(-600), watermark]
        await service.pollDueCommunityFollows(asOf: now, postDatesFetcher: { _, _ in dates })

        let postNowCalls = await scheduler.postNowCalls
        #expect(postNowCalls.isEmpty)

        let stored = try storedFollow(appDatabase)
        #expect(stored.status == ReminderRecord.Status.scheduled.rawValue)
        #expect(stored.unseen == false)

        // Watermark untouched.
        let baselineAt = try #require(stored.baselineAt)
        #expect(abs(baselineAt.timeIntervalSince1970 - watermark.timeIntervalSince1970) < 1)

        // nextCheckAt bumped forward regardless.
        let nextCheckAt = try #require(stored.nextCheckAt)
        let expectedNextCheckAt = now.addingTimeInterval(CommunityFollowRule.pollInterval)
        #expect(abs(nextCheckAt.timeIntervalSince1970 - expectedNextCheckAt.timeIntervalSince1970) < 1)
    }

    @Test
    func pollBumpsOnFetchFailure() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let watermark = now.addingTimeInterval(-3600)
        try await seedCommunityFollow(
            appDatabase,
            baselineAt: watermark,
            nextCheckAt: now.addingTimeInterval(-60)
        )

        await service.pollDueCommunityFollows(asOf: now, postDatesFetcher: { _, _ in nil })

        let postNowCalls = await scheduler.postNowCalls
        #expect(postNowCalls.isEmpty)

        let stored = try storedFollow(appDatabase)
        #expect(stored.status == ReminderRecord.Status.scheduled.rawValue)

        // Watermark untouched.
        let baselineAt = try #require(stored.baselineAt)
        #expect(abs(baselineAt.timeIntervalSince1970 - watermark.timeIntervalSince1970) < 1)

        // nextCheckAt still bumped so the follow is retried next sweep.
        let nextCheckAt = try #require(stored.nextCheckAt)
        let expectedNextCheckAt = now.addingTimeInterval(CommunityFollowRule.pollInterval)
        #expect(abs(nextCheckAt.timeIntervalSince1970 - expectedNextCheckAt.timeIntervalSince1970) < 1)
    }

    @Test
    func pollHonorsThrottle() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let watermark = now.addingTimeInterval(-3600)
        let futureNextCheckAt = now.addingTimeInterval(600) // not yet due
        try await seedCommunityFollow(
            appDatabase,
            baselineAt: watermark,
            nextCheckAt: futureNextCheckAt
        )

        final class InvocationCounter: @unchecked Sendable {
            @Atomic var count = 0
        }
        let counter = InvocationCounter()

        await service.pollDueCommunityFollows(asOf: now, postDatesFetcher: { _, _ in
            counter.count += 1
            return [now]
        })

        #expect(counter.count == 0)

        let postNowCalls = await scheduler.postNowCalls
        #expect(postNowCalls.isEmpty)

        let stored = try storedFollow(appDatabase)
        #expect(stored.status == ReminderRecord.Status.scheduled.rawValue)
        // nextCheckAt is unchanged (not bumped) - the row was never processed.
        let nextCheckAt = try #require(stored.nextCheckAt)
        #expect(abs(nextCheckAt.timeIntervalSince1970 - futureNextCheckAt.timeIntervalSince1970) < 1)
    }
}
