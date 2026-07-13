//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

/// Coverage for `ReminderService.setActivityReminder`/`removeActivityReminder`
/// (Phase 2 Task 1) - the whole-post "notify me as the discussion grows"
/// create/remove pair. Unlike `setTimeReminder`, activity reminders schedule
/// no up-front `UNCalendarNotificationTrigger` (they fire from the foreground
/// poll added in a later task), so these tests assert the row lands with its
/// baseline/poll fields set and that the fake scheduler's `schedule` is never
/// called. Reuses the `FakeReminderNotificationScheduler` declared in
/// `ReminderServiceTests`.
struct ReminderServiceActivityTests {
    private static let accountId: Int64 = 1
    private static let postServerId: Int64 = 100
    private static let apId = "https://example.com/post/100"

    private func makeService(
        appDatabase: AppDatabase,
        scheduler: ReminderServiceTests.FakeReminderNotificationScheduler,
        notificationsEnabled: @escaping @Sendable () -> Bool = { true }
    ) -> ReminderService {
        ReminderService(
            accountId: Self.accountId,
            appDatabase: appDatabase,
            scheduler: scheduler,
            notificationsEnabled: notificationsEnabled
        )
    }

    // MARK: - setActivityReminder

    @Test
    func setActivityReminderPersistsScheduledRowWithBaselineAndNoSchedulerCall() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let before = Date()
        try await service.setActivityReminder(
            postServerId: Self.postServerId,
            apId: Self.apId,
            baselineCount: 12,
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: "https://example.com/thumb.jpg"
        )

        let stored = try #require(appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.activity.rawValue
        ))
        #expect(stored.status == ReminderRecord.Status.scheduled.rawValue)
        #expect(stored.baselineCount == 12)
        #expect(stored.notificationRequestId == nil)
        #expect(stored.titleSnapshot == "A post title")
        #expect(stored.communityName == "news")
        #expect(stored.instanceHost == "example.com")
        #expect(stored.thumbnailUrl == "https://example.com/thumb.jpg")

        // GRDB round-trips `Date` through ISO-8601 text (see the project's
        // GRDB date-storage convention), which can lose sub-second precision -
        // compare with a tolerance rather than a strict `before`/`after`
        // bound, matching the pattern used for `fireAt` in `ReminderServiceTests`.
        let baselineAt = try #require(stored.baselineAt)
        #expect(abs(baselineAt.timeIntervalSince1970 - before.timeIntervalSince1970) < 2)

        let nextCheckAt = try #require(stored.nextCheckAt)
        let expectedNextCheckAt = baselineAt.addingTimeInterval(ReminderActivityRule.pollInterval)
        #expect(abs(nextCheckAt.timeIntervalSince1970 - expectedNextCheckAt.timeIntervalSince1970) < 1)

        // Activity reminders fire from the foreground poll (a later task), not
        // an up-front OS trigger - `schedule` must never be called here.
        let calls = await scheduler.scheduleCalls
        #expect(calls.isEmpty)
    }

    /// A second `setActivityReminder` for the same post replaces the row (not
    /// a duplicate) and re-baselines it - mirrors
    /// `secondSetTimeReminderForSamePostReplacesRowAndReschedules`.
    @Test
    func secondSetActivityReminderForSamePostReplacesRowAndRebaselines() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        try await service.setActivityReminder(
            postServerId: Self.postServerId,
            apId: Self.apId,
            baselineCount: 5,
            titleSnapshot: "Original title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )
        try await service.setActivityReminder(
            postServerId: Self.postServerId,
            apId: Self.apId,
            baselineCount: 9,
            titleSnapshot: "Updated title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )

        let rowCount = try await appDatabase.writer.read { db in
            try ReminderRecord.fetchCount(db)
        }
        #expect(rowCount == 1)

        let stored = try #require(appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.activity.rawValue
        ))
        #expect(stored.baselineCount == 9)
        #expect(stored.titleSnapshot == "Updated title")
    }

    /// Permission denial never blocks persistence - mirrors
    /// `permissionDeniedStillPersistsRecordWithoutThrowing` for the time kind.
    @Test
    func setActivityReminderPersistsRowEvenWhenAuthorizationDenied() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        await scheduler.setGranted(false)
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

        let stored = try #require(appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.activity.rawValue
        ))
        #expect(stored.status == ReminderRecord.Status.scheduled.rawValue)

        let calls = await scheduler.scheduleCalls
        #expect(calls.isEmpty)
    }

    // MARK: - removeActivityReminder

    @Test
    func removeActivityReminderDeletesRow() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        try await service.setActivityReminder(
            postServerId: Self.postServerId,
            apId: Self.apId,
            baselineCount: 4,
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )

        try await service.removeActivityReminder(postServerId: Self.postServerId)

        let stored = appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.activity.rawValue
        )
        #expect(stored == nil)

        // There is no OS request to cancel - `notificationRequestId` is nil
        // for an activity reminder, so `cancel` must never be called.
        let cancelCalls = await scheduler.cancelCalls
        #expect(cancelCalls.isEmpty)
    }

    /// Removing a target with no activity reminder is a no-op: no throw.
    @Test
    func removeActivityReminderOnMissingReminderIsNoOp() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        try await service.removeActivityReminder(postServerId: 999)

        let cancelCalls = await scheduler.cancelCalls
        #expect(cancelCalls.isEmpty)
    }

    /// A whole-post time reminder and an activity reminder on the same post
    /// are independent rows (different `kind`) - removing one must not touch
    /// the other.
    @Test
    func timeAndActivityReminderOnSamePostAreIndependent() async throws {
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
        try await service.setActivityReminder(
            postServerId: Self.postServerId,
            apId: Self.apId,
            baselineCount: 2,
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )

        try await service.removeActivityReminder(postServerId: Self.postServerId)

        let timeReminder = appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.time.rawValue
        )
        #expect(timeReminder != nil)

        let activityReminder = appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.activity.rawValue
        )
        #expect(activityReminder == nil)
    }
}
