//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import Testing
@testable import SpudDataKit

/// Coverage for the Phase 2 activity-reminder poll
/// (`ReminderService.pollDueActivityReminders`) and the pure activity
/// notification content (`ReminderNotificationFactory.activityReminderContent`).
///
/// The poll tests seed a due `activity` row into an `AppDatabase.inMemory()`,
/// drive the poll with a deterministic `asOf` + an injected comment-count
/// fetcher, and assert on the resulting row state plus the
/// `FakeReminderNotificationScheduler`'s recorded `postNow` calls. Reuses the
/// fake declared in `ReminderServiceTests`.
struct ReminderPollTests {
    private static let accountId: Int64 = 1
    private static let postServerId: Int64 = 100
    private static let apId = "https://example.com/post/100"

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

    /// Inserts a single whole-post `activity` reminder directly (bypassing
    /// `setActivityReminder` so `baselineAt`/`nextCheckAt` can be pinned to
    /// exact deterministic values rather than the wall clock).
    @discardableResult
    private func seedActivityReminder(
        _ appDatabase: AppDatabase,
        baselineCount: Int64,
        baselineAt: Date,
        nextCheckAt: Date,
        status: ReminderRecord.Status = .scheduled,
        postServerId: Int64 = ReminderPollTests.postServerId
    ) async throws -> Int64 {
        let record = ReminderRecord(
            accountId: Self.accountId,
            postServerId: postServerId,
            apId: Self.apId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.activity.rawValue,
            nextCheckAt: nextCheckAt,
            baselineCount: baselineCount,
            baselineAt: baselineAt,
            status: status.rawValue,
            unseen: false,
            notificationRequestId: nil,
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: nil
        )
        return try await appDatabase.upsertReminder(record)
    }

    private func storedActivityReminder(
        _ appDatabase: AppDatabase,
        postServerId: Int64 = ReminderPollTests.postServerId
    ) throws -> ReminderRecord {
        try #require(appDatabase.reminderSync(
            accountId: Self.accountId,
            postServerId: postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.activity.rawValue
        ))
    }

    // MARK: - Fires on >= threshold new comments

    @Test
    func firesWhenThresholdNewCommentsLanded() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let id = try await seedActivityReminder(
            appDatabase,
            baselineCount: 10,
            baselineAt: now.addingTimeInterval(-3600), // now - 1h
            nextCheckAt: now.addingTimeInterval(-60) // now - 1m (due)
        )

        // 16 - 10 = 6 new comments, over the threshold of 5.
        await service.pollDueActivityReminders(asOf: now, commentCountFetcher: { _, _ in 16 })

        // Fired: an immediate notification posted with the "6 new comments" body.
        let postNowCalls = await scheduler.postNowCalls
        #expect(postNowCalls.count == 1)
        let call = try #require(postNowCalls.first)
        #expect(call.content.title == "A post title")
        #expect(call.content.body.contains("6 new comments"))
        #expect(call.content.body.contains("c/news@example.com"))

        // Row re-armed: fired + unseen, baseline reset to the just-observed 16,
        // and nextCheckAt pushed forward by the poll interval.
        let stored = try storedActivityReminder(appDatabase)
        #expect(stored.id == id)
        #expect(stored.status == ReminderRecord.Status.fired.rawValue)
        #expect(stored.unseen == true)
        #expect(stored.baselineCount == 16)

        let baselineAt = try #require(stored.baselineAt)
        #expect(abs(baselineAt.timeIntervalSince1970 - now.timeIntervalSince1970) < 1)

        let nextCheckAt = try #require(stored.nextCheckAt)
        let expectedNextCheckAt = now.addingTimeInterval(ReminderActivityRule.pollInterval)
        #expect(abs(nextCheckAt.timeIntervalSince1970 - expectedNextCheckAt.timeIntervalSince1970) < 1)

        let lastNotifiedAt = try #require(stored.lastNotifiedAt)
        #expect(abs(lastNotifiedAt.timeIntervalSince1970 - now.timeIntervalSince1970) < 1)
    }

    // MARK: - No fire below threshold and before fallback

    @Test
    func doesNotFireBelowThresholdBeforeFallback() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await seedActivityReminder(
            appDatabase,
            baselineCount: 10,
            baselineAt: now.addingTimeInterval(-3600), // now - 1h, under the 24h fallback
            nextCheckAt: now.addingTimeInterval(-60)
        )

        // 11 - 10 = 1 new comment: below threshold and elapsed (1h) < fallback.
        await service.pollDueActivityReminders(asOf: now, commentCountFetcher: { _, _ in 11 })

        let postNowCalls = await scheduler.postNowCalls
        #expect(postNowCalls.isEmpty)

        let stored = try storedActivityReminder(appDatabase)
        // No fire: still scheduled, baseline unchanged.
        #expect(stored.status == ReminderRecord.Status.scheduled.rawValue)
        #expect(stored.unseen == false)
        #expect(stored.baselineCount == 10)
        #expect(stored.lastNotifiedAt == nil)

        // nextCheckAt bumped forward regardless.
        let nextCheckAt = try #require(stored.nextCheckAt)
        let expectedNextCheckAt = now.addingTimeInterval(ReminderActivityRule.pollInterval)
        #expect(abs(nextCheckAt.timeIntervalSince1970 - expectedNextCheckAt.timeIntervalSince1970) < 1)
    }

    // MARK: - Fires on the 24h fallback with only a few new comments

    @Test
    func firesOnFallbackAfter24Hours() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await seedActivityReminder(
            appDatabase,
            baselineCount: 10,
            baselineAt: now.addingTimeInterval(-25 * 3600), // now - 25h, over the 24h fallback
            nextCheckAt: now.addingTimeInterval(-60)
        )

        // 13 - 10 = 3 new comments: below threshold, but elapsed (25h) >= fallback.
        await service.pollDueActivityReminders(asOf: now, commentCountFetcher: { _, _ in 13 })

        let postNowCalls = await scheduler.postNowCalls
        #expect(postNowCalls.count == 1)
        let call = try #require(postNowCalls.first)
        #expect(call.content.body.contains("3 new comments"))

        let stored = try storedActivityReminder(appDatabase)
        #expect(stored.status == ReminderRecord.Status.fired.rawValue)
        #expect(stored.unseen == true)
        #expect(stored.baselineCount == 13)
    }

    // MARK: - Fetch failure

    @Test
    func fetchFailureDoesNotFireButBumpsNextCheck() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await seedActivityReminder(
            appDatabase,
            baselineCount: 10,
            baselineAt: now.addingTimeInterval(-25 * 3600), // even past the fallback, a nil fetch never fires
            nextCheckAt: now.addingTimeInterval(-60)
        )

        await service.pollDueActivityReminders(asOf: now, commentCountFetcher: { _, _ in nil })

        let postNowCalls = await scheduler.postNowCalls
        #expect(postNowCalls.isEmpty)

        let stored = try storedActivityReminder(appDatabase)
        #expect(stored.status == ReminderRecord.Status.scheduled.rawValue)
        #expect(stored.baselineCount == 10)

        // nextCheckAt is still bumped so the follow is retried next sweep.
        let nextCheckAt = try #require(stored.nextCheckAt)
        let expectedNextCheckAt = now.addingTimeInterval(ReminderActivityRule.pollInterval)
        #expect(abs(nextCheckAt.timeIntervalSince1970 - expectedNextCheckAt.timeIntervalSince1970) < 1)
    }

    // MARK: - Not-due rows are untouched

    @Test
    func notDueReminderIsLeftUntouched() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let futureNextCheckAt = now.addingTimeInterval(600) // 10 min in the future - not yet due
        try await seedActivityReminder(
            appDatabase,
            baselineCount: 10,
            baselineAt: now.addingTimeInterval(-25 * 3600),
            nextCheckAt: futureNextCheckAt
        )

        // Even a huge new-comment count must not fire a not-due row: the fetcher
        // should never even be consulted (nextCheckAt is in the future).
        await service.pollDueActivityReminders(asOf: now, commentCountFetcher: { _, _ in 9999 })

        let postNowCalls = await scheduler.postNowCalls
        #expect(postNowCalls.isEmpty)

        let stored = try storedActivityReminder(appDatabase)
        #expect(stored.status == ReminderRecord.Status.scheduled.rawValue)
        #expect(stored.baselineCount == 10)
        // nextCheckAt is unchanged (not bumped) - the row was never processed.
        let nextCheckAt = try #require(stored.nextCheckAt)
        #expect(abs(nextCheckAt.timeIntervalSince1970 - futureNextCheckAt.timeIntervalSince1970) < 1)
    }

    // MARK: - Already-fired rows keep polling

    /// A previously-fired (re-armed) follow with a due `nextCheckAt` is still
    /// polled - `dueActivityRemindersSync` includes `status = fired` rows.
    @Test
    func alreadyFiredReminderIsStillPolledAndCanRefire() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let scheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let service = makeService(appDatabase: appDatabase, scheduler: scheduler)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await seedActivityReminder(
            appDatabase,
            baselineCount: 16,
            baselineAt: now.addingTimeInterval(-3600),
            nextCheckAt: now.addingTimeInterval(-60),
            status: .fired
        )

        // 22 - 16 = 6 new since the last fire's baseline -> refires.
        await service.pollDueActivityReminders(asOf: now, commentCountFetcher: { _, _ in 22 })

        let postNowCalls = await scheduler.postNowCalls
        #expect(postNowCalls.count == 1)

        let stored = try storedActivityReminder(appDatabase)
        #expect(stored.status == ReminderRecord.Status.fired.rawValue)
        #expect(stored.baselineCount == 22)
    }

    // MARK: - activityReminderContent (pure)

    @Test
    func activityReminderContentPluralizesAndDeepLinks() throws {
        let single = ReminderNotificationFactory.activityReminderContent(
            titleSnapshot: "A great thread",
            communityName: "news",
            instanceHost: "example.com",
            apId: Self.apId,
            newCount: 1
        )
        #expect(single.title == "A great thread")
        #expect(single.body == "1 new comment · c/news@example.com")

        let plural = ReminderNotificationFactory.activityReminderContent(
            titleSnapshot: "A great thread",
            communityName: "news",
            instanceHost: "example.com",
            apId: Self.apId,
            newCount: 6
        )
        #expect(plural.body == "6 new comments · c/news@example.com")

        // routingURL is the objectAtURL deep-link of the apId.
        let expected = try URL.SpudInternalLink.objectAtURL(url: #require(URL(string: Self.apId))).url.absoluteString
        #expect(plural.routingURLString == expected)
    }
}
