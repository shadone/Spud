//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

/// Coverage for `ReminderService` - the per-account actor tying the durable
/// `reminder` table (`ReminderWrites.swift`) together with an injected
/// `ReminderNotificationScheduling`. `FakeReminderNotificationScheduler`
/// records every `schedule`/`cancel` call and exposes a settable `granted`
/// flag so the permission-denied path can be exercised without a
/// simulator/device.
struct ReminderServiceTests {
    // MARK: - Fake scheduler

    /// An actor (not a plain class) so it stays `Sendable` under strict
    /// concurrency while still letting the test await its recorded calls
    /// after driving the service under test.
    actor FakeReminderNotificationScheduler: ReminderNotificationScheduling {
        /// Settable authorization state - flip to `false` to exercise the
        /// permission-denied path.
        var granted = true
        private(set) var scheduleCalls: [(requestId: String, fireAt: Date, content: ReminderNotificationContent)] = []
        private(set) var cancelCalls: [String] = []

        func requestAuthorization() async -> Bool {
            granted
        }

        func authorizationGranted() async -> Bool {
            granted
        }

        func schedule(requestId: String, fireAt: Date, content: ReminderNotificationContent) async {
            scheduleCalls.append((requestId: requestId, fireAt: fireAt, content: content))
        }

        func cancel(requestId: String) async {
            cancelCalls.append(requestId)
        }
    }

    // MARK: - Helpers

    private static let accountId: Int64 = 1
    private static let postServerId: Int64 = 100
    private static let apId = "https://example.com/post/100"
    private static let expectedRequestId = "reminder-1-100-0-time"

    private func makeService(
        appDatabase: AppDatabase,
        scheduler: FakeReminderNotificationScheduler,
        notificationsEnabled: @escaping @Sendable () -> Bool = { true }
    ) -> ReminderService {
        ReminderService(
            accountId: Self.accountId,
            appDatabase: appDatabase,
            scheduler: scheduler,
            notificationsEnabled: notificationsEnabled
        )
    }

    // MARK: - setTimeReminder

    @Test
    func setTimeReminderPersistsScheduledRecordAndSchedulesNotification() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let fireAt = Date(timeIntervalSince1970: 1_800_000_000)
        try await service.setTimeReminder(
            postServerId: Self.postServerId,
            apId: Self.apId,
            fireAt: fireAt,
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: "https://example.com/thumb.jpg"
        )

        let stored = try #require(appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.time.rawValue
        ))
        #expect(stored.status == ReminderRecord.Status.scheduled.rawValue)
        #expect(stored.notificationRequestId == Self.expectedRequestId)
        #expect(stored.titleSnapshot == "A post title")
        #expect(stored.communityName == "news")
        #expect(stored.instanceHost == "example.com")
        let storedFireAt = try #require(stored.fireAt)
        #expect(abs(storedFireAt.timeIntervalSince1970 - fireAt.timeIntervalSince1970) < 1)

        let calls = await scheduler.scheduleCalls
        #expect(calls.count == 1)
        let call = try #require(calls.first)
        #expect(call.requestId == Self.expectedRequestId)
        #expect(abs(call.fireAt.timeIntervalSince1970 - fireAt.timeIntervalSince1970) < 1)
        let expectedContent = ReminderNotificationFactory.timeReminderContent(
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            apId: Self.apId
        )
        #expect(call.content == expectedContent)
    }

    /// A second `setTimeReminder` for the same post must replace, not
    /// duplicate, the row - and must re-schedule the OS notification under the
    /// same stable request id (which naturally replaces the pending request).
    @Test
    func secondSetTimeReminderForSamePostReplacesRowAndReschedules() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let firstFireAt = Date(timeIntervalSince1970: 1_800_000_000)
        try await service.setTimeReminder(
            postServerId: Self.postServerId,
            apId: Self.apId,
            fireAt: firstFireAt,
            titleSnapshot: "Original title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )

        let secondFireAt = Date(timeIntervalSince1970: 1_900_000_000)
        try await service.setTimeReminder(
            postServerId: Self.postServerId,
            apId: Self.apId,
            fireAt: secondFireAt,
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
            kind: ReminderRecord.Kind.time.rawValue
        ))
        #expect(stored.titleSnapshot == "Updated title")
        let storedFireAt = try #require(stored.fireAt)
        #expect(abs(storedFireAt.timeIntervalSince1970 - secondFireAt.timeIntervalSince1970) < 1)

        let calls = await scheduler.scheduleCalls
        #expect(calls.count == 2)
        #expect(calls.allSatisfy { $0.requestId == Self.expectedRequestId })
        let lastFireAt = try #require(calls.last?.fireAt)
        #expect(abs(lastFireAt.timeIntervalSince1970 - secondFireAt.timeIntervalSince1970) < 1)
    }

    // MARK: - removeTimeReminder

    @Test
    func removeTimeReminderDeletesRowAndCancelsStoredRequestId() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = FakeReminderNotificationScheduler()
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

        try await service.removeTimeReminder(postServerId: Self.postServerId)

        let stored = appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.time.rawValue
        )
        #expect(stored == nil)

        let cancelCalls = await scheduler.cancelCalls
        #expect(cancelCalls == [Self.expectedRequestId])
    }

    /// Removing a target with no reminder is a no-op: no throw, and the
    /// scheduler's `cancel` is never called (there's no stored request id to
    /// cancel).
    @Test
    func removeTimeReminderOnMissingReminderIsNoOp() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        try await service.removeTimeReminder(postServerId: 999)

        let cancelCalls = await scheduler.cancelCalls
        #expect(cancelCalls.isEmpty)
    }

    // MARK: - Permission denied

    /// When the OS denies (or the user has disabled) reminder notifications,
    /// the reminder is still persisted in-app - `setTimeReminder` must not
    /// throw, and no OS notification is scheduled.
    @Test
    func permissionDeniedStillPersistsRecordWithoutThrowing() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = FakeReminderNotificationScheduler()
        await scheduler.setGranted(false)
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

        let stored = try #require(appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.time.rawValue
        ))
        #expect(stored.status == ReminderRecord.Status.scheduled.rawValue)
        #expect(stored.notificationRequestId == Self.expectedRequestId)

        let calls = await scheduler.scheduleCalls
        #expect(calls.isEmpty)
    }

    /// The `notificationsEnabled` injection seam (standing in for
    /// `PreferencesService.reminderNotificationsEnabled` - see
    /// `ReminderService`'s doc comment for why it can't read the real
    /// preference directly) gates scheduling the same way a denied OS
    /// permission does, without ever prompting for authorization.
    @Test
    func notificationsDisabledPreferenceSkipsSchedulingWithoutPrompting() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler, notificationsEnabled: { false })

        try await service.setTimeReminder(
            postServerId: Self.postServerId,
            apId: Self.apId,
            fireAt: Date(timeIntervalSince1970: 1_800_000_000),
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )

        let stored = appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.time.rawValue
        )
        #expect(stored != nil)

        let calls = await scheduler.scheduleCalls
        #expect(calls.isEmpty)
    }

    // MARK: - reconcileOverdue

    @Test
    func reconcileOverdueFlipsPastScheduledReminderToFiredUnseen() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let pastFireAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await service.setTimeReminder(
            postServerId: Self.postServerId,
            apId: Self.apId,
            fireAt: pastFireAt,
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )

        let futureAsOf = Date(timeIntervalSince1970: 1_800_000_000)
        try await service.reconcileOverdue(asOf: futureAsOf)

        let stored = try #require(appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.time.rawValue
        ))
        #expect(stored.status == ReminderRecord.Status.fired.rawValue)
        #expect(stored.unseen == true)
    }
}

extension ReminderServiceTests.FakeReminderNotificationScheduler {
    /// Test-only mutator for `granted` - not `private` (unlike a plain
    /// property write, which would need no such helper) because this is an
    /// `extension`, and `ReminderServiceActivityTests` (a sibling test file)
    /// also drives the permission-denied path via this fake.
    func setGranted(_ value: Bool) {
        granted = value
    }
}
