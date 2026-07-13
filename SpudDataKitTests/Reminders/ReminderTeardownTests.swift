//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// Coverage for `ReminderService.removeAllReminders()` - the account-teardown
/// cleanup (Phase 4) called by `AccountService.logout`/`removeAccount` before
/// an account row is deleted, since `reminder.accountId` carries no cascading
/// foreign key. Reuses `ReminderServiceTests.FakeReminderNotificationScheduler`
/// (records every `cancel` call) and a fresh `AppDatabase.inMemory()` per test.
struct ReminderTeardownTests {
    private static let accountId: Int64 = 1
    private static let otherAccountId: Int64 = 2

    @Test
    func removeAllRemindersDeletesEveryRowAndCancelsStoredTimeRequestIds() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = ReminderService(accountId: Self.accountId, appDatabase: appDatabase, scheduler: scheduler)

        // Two whole-post time reminders (each schedules an OS notification,
        // persisting a notificationRequestId) plus one whole-post activity
        // follow (never persists a notificationRequestId - see
        // `ReminderService.setActivityReminder`).
        try await service.setTimeReminder(
            postServerId: 100,
            apId: "https://example.com/post/100",
            fireAt: Date(timeIntervalSince1970: 1_800_000_000),
            titleSnapshot: "First post",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )
        try await service.setTimeReminder(
            postServerId: 200,
            apId: "https://example.com/post/200",
            fireAt: Date(timeIntervalSince1970: 1_800_000_001),
            titleSnapshot: "Second post",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )
        try await service.setActivityReminder(
            postServerId: 300,
            apId: "https://example.com/post/300",
            baselineCount: 5,
            titleSnapshot: "Third post",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )

        // A second account's reminders must survive this account's teardown.
        let otherScheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let otherService = ReminderService(accountId: Self.otherAccountId, appDatabase: appDatabase, scheduler: otherScheduler)
        try await otherService.setTimeReminder(
            postServerId: 400,
            apId: "https://example.com/post/400",
            fireAt: Date(timeIntervalSince1970: 1_800_000_002),
            titleSnapshot: "Other account's post",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )

        await service.removeAllReminders()

        // All three of this account's rows are gone, across both kinds.
        #expect(appDatabase.reminderSync(
            accountId: Self.accountId, postServerId: 100, rootCommentServerId: 0, kind: ReminderRecord.Kind.time.rawValue
        ) == nil)
        #expect(appDatabase.reminderSync(
            accountId: Self.accountId, postServerId: 200, rootCommentServerId: 0, kind: ReminderRecord.Kind.time.rawValue
        ) == nil)
        #expect(appDatabase.reminderSync(
            accountId: Self.accountId, postServerId: 300, rootCommentServerId: 0, kind: ReminderRecord.Kind.activity.rawValue
        ) == nil)

        let remainingCountForAccount = try await appDatabase.writer.read { db in
            try ReminderRecord.filter(Column("accountId") == Self.accountId).fetchCount(db)
        }
        #expect(remainingCountForAccount == 0)

        // Only the two TIME reminders' stored notificationRequestIds are
        // cancelled - the activity reminder never had one to cancel.
        let cancelCalls = await scheduler.cancelCalls
        #expect(Set(cancelCalls) == ["reminder-1-100-0-time", "reminder-1-200-0-time"])
        #expect(cancelCalls.count == 2)

        // The second account's reminder, and its scheduler, are untouched.
        let otherReminder = appDatabase.reminderSync(
            accountId: Self.otherAccountId, postServerId: 400, rootCommentServerId: 0, kind: ReminderRecord.Kind.time.rawValue
        )
        #expect(otherReminder != nil)
        let otherCancelCalls = await otherScheduler.cancelCalls
        #expect(otherCancelCalls.isEmpty)
    }

    /// An account with no reminders at all is a no-op - no throw, no crash on
    /// an empty requestId list, nothing to cancel.
    @Test
    func removeAllRemindersOnAccountWithNoRemindersIsNoOp() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = ReminderService(accountId: Self.accountId, appDatabase: appDatabase, scheduler: scheduler)

        await service.removeAllReminders()

        let cancelCalls = await scheduler.cancelCalls
        #expect(cancelCalls.isEmpty)
    }
}
