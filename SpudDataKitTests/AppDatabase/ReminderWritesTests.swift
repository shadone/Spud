//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// Coverage for the reminder writes (`ReminderWrites.swift`), sync reads
/// (`ReminderQueries.swift`), and observations (`ReminderObservations.swift`).
/// `reminder.accountId` carries no foreign key (mirrors `postInteraction`'s
/// plain-integer `postServerId`; see `ReminderRecordTests`), so these tests
/// don't need to seed instance/site/account rows.
struct ReminderWritesTests {
    // MARK: - Helpers

    private static func makeRecord(
        accountId: Int64 = 1,
        postServerId: Int64 = 100,
        rootCommentServerId: Int64 = ReminderRecord.wholePostSentinel,
        kind: ReminderRecord.Kind = .time,
        fireAt: Date? = Date(timeIntervalSince1970: 1_800_000_000),
        status: ReminderRecord.Status = .scheduled,
        unseen: Bool = false,
        notificationRequestId: String? = "reminder-1-100-0-time",
        titleSnapshot: String = "A post title"
    ) -> ReminderRecord {
        ReminderRecord(
            accountId: accountId,
            postServerId: postServerId,
            apId: "https://example.com/post/\(postServerId)",
            rootCommentServerId: rootCommentServerId,
            kind: kind.rawValue,
            fireAt: fireAt,
            status: status.rawValue,
            unseen: unseen,
            notificationRequestId: notificationRequestId,
            titleSnapshot: titleSnapshot,
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: "https://example.com/thumb.jpg"
        )
    }

    // MARK: - upsertReminder / reminderSync

    @Test
    func upsertThenReminderSyncReturnsIt() async throws {
        let db = try AppDatabase.inMemory()
        let record = Self.makeRecord()

        let insertedId = try await db.upsertReminder(record)
        #expect(insertedId > 0)

        let fetched = db.reminderSync(
            accountId: record.accountId,
            postServerId: record.postServerId,
            rootCommentServerId: record.rootCommentServerId,
            kind: record.kind
        )
        let unwrapped = try #require(fetched)
        #expect(unwrapped.id == insertedId)
        #expect(unwrapped.titleSnapshot == record.titleSnapshot)
        #expect(unwrapped.status == ReminderRecord.Status.scheduled.rawValue)
    }

    /// Upserting the same unique key twice must not create a second row - the
    /// second call replaces the first row's mutable fields in place.
    @Test
    func upsertSameKeyTwiceReplacesInPlace() async throws {
        let db = try AppDatabase.inMemory()
        let first = Self.makeRecord(titleSnapshot: "Original title")

        let firstId = try await db.upsertReminder(first)

        let second = Self.makeRecord(
            fireAt: Date(timeIntervalSince1970: 1_900_000_000),
            notificationRequestId: "reminder-1-100-0-time-v2",
            titleSnapshot: "Updated title"
        )
        let secondId = try await db.upsertReminder(second)

        // Same row - the id is stable across the upsert.
        #expect(secondId == firstId)

        let count = try await db.writer.read { db in
            try ReminderRecord.fetchCount(db)
        }
        #expect(count == 1)

        let fetched = try #require(db.reminderSync(
            accountId: second.accountId,
            postServerId: second.postServerId,
            rootCommentServerId: second.rootCommentServerId,
            kind: second.kind
        ))
        #expect(fetched.titleSnapshot == "Updated title")
        #expect(fetched.notificationRequestId == "reminder-1-100-0-time-v2")
        let fetchedFireAt = try #require(fetched.fireAt)
        #expect(abs(fetchedFireAt.timeIntervalSince1970 - 1_900_000_000) < 1)
    }

    // MARK: - removeReminder

    @Test
    func removeReminderDeletesAndReturnsNotificationRequestId() async throws {
        let db = try AppDatabase.inMemory()
        let record = Self.makeRecord(notificationRequestId: "reminder-to-cancel")
        _ = try await db.upsertReminder(record)

        let removedRequestId = try await db.removeReminder(
            accountId: record.accountId,
            postServerId: record.postServerId,
            rootCommentServerId: record.rootCommentServerId,
            kind: record.kind
        )
        #expect(removedRequestId == "reminder-to-cancel")

        let fetched = db.reminderSync(
            accountId: record.accountId,
            postServerId: record.postServerId,
            rootCommentServerId: record.rootCommentServerId,
            kind: record.kind
        )
        #expect(fetched == nil)
    }

    /// Removing a target with no reminder is a no-op that returns nil (not a
    /// throw) - the "Remind Me…" menu's cancel action can call it unconditionally.
    @Test
    func removeReminderOnMissingRowReturnsNil() async throws {
        let db = try AppDatabase.inMemory()

        let result = try await db.removeReminder(
            accountId: 1, postServerId: 999, rootCommentServerId: ReminderRecord.wholePostSentinel, kind: "time"
        )
        #expect(result == nil)
    }

    // MARK: - markReminderFired

    @Test
    func markReminderFiredSetsStatusUnseenAndLastNotifiedAt() async throws {
        let db = try AppDatabase.inMemory()
        let record = Self.makeRecord(status: .scheduled, unseen: false)
        let id = try await db.upsertReminder(record)

        let firedAt = Date(timeIntervalSince1970: 1_850_000_000)
        try await db.markReminderFired(id: id, firedAt: firedAt)

        let fetched = try #require(db.reminderSync(
            accountId: record.accountId,
            postServerId: record.postServerId,
            rootCommentServerId: record.rootCommentServerId,
            kind: record.kind
        ))
        #expect(fetched.status == ReminderRecord.Status.fired.rawValue)
        #expect(fetched.unseen == true)
        let lastNotifiedAt = try #require(fetched.lastNotifiedAt)
        #expect(abs(lastNotifiedAt.timeIntervalSince1970 - firedAt.timeIntervalSince1970) < 1)
    }

    // MARK: - markRemindersSeen

    @Test
    func markRemindersSeenClearsUnseenOnFiredReminders() async throws {
        let db = try AppDatabase.inMemory()
        let record = Self.makeRecord(status: .fired, unseen: true)
        _ = try await db.upsertReminder(record)

        #expect(db.unseenReminderCountSync(accountId: record.accountId) == 1)

        try await db.markRemindersSeen(accountId: record.accountId)

        #expect(db.unseenReminderCountSync(accountId: record.accountId) == 0)
        let fetched = try #require(db.reminderSync(
            accountId: record.accountId,
            postServerId: record.postServerId,
            rootCommentServerId: record.rootCommentServerId,
            kind: record.kind
        ))
        #expect(fetched.unseen == false)
        // Status is untouched by markRemindersSeen - only unseen changes.
        #expect(fetched.status == ReminderRecord.Status.fired.rawValue)
    }

    // MARK: - reconcileOverdueTimeReminders

    /// Flips only rows that are simultaneously: `kind == .time`,
    /// `status == .scheduled`, and `fireAt <= asOf`. A future-`fireAt` time
    /// reminder and a same-target `activity`-kind reminder must be untouched.
    @Test
    func reconcileOverdueTimeRemindersFlipsOnlyPastScheduledTimeRows() async throws {
        let db = try AppDatabase.inMemory()
        let asOf = Date(timeIntervalSince1970: 1_800_000_000)

        let overduePastTime = Self.makeRecord(
            postServerId: 1, kind: .time, fireAt: Date(timeIntervalSince1970: 1_700_000_000), status: .scheduled
        )
        let futureTime = Self.makeRecord(
            postServerId: 2, kind: .time, fireAt: Date(timeIntervalSince1970: 1_900_000_000), status: .scheduled
        )
        let overdueActivity = Self.makeRecord(
            postServerId: 3, kind: .activity, fireAt: Date(timeIntervalSince1970: 1_700_000_000), status: .scheduled
        )
        let alreadyFired = Self.makeRecord(
            postServerId: 4, kind: .time, fireAt: Date(timeIntervalSince1970: 1_600_000_000), status: .fired
        )

        _ = try await db.upsertReminder(overduePastTime)
        _ = try await db.upsertReminder(futureTime)
        _ = try await db.upsertReminder(overdueActivity)
        _ = try await db.upsertReminder(alreadyFired)

        let flipped = try await db.reconcileOverdueTimeReminders(accountId: 1, asOf: asOf)

        #expect(flipped.count == 1)
        #expect(flipped.first?.postServerId == 1)
        #expect(flipped.first?.status == ReminderRecord.Status.fired.rawValue)
        #expect(flipped.first?.unseen == true)

        // Untouched rows keep their original status.
        let future = try #require(db.reminderSync(accountId: 1, postServerId: 2, rootCommentServerId: 0, kind: "time"))
        #expect(future.status == ReminderRecord.Status.scheduled.rawValue)

        let activity = try #require(db.reminderSync(accountId: 1, postServerId: 3, rootCommentServerId: 0, kind: "activity"))
        #expect(activity.status == ReminderRecord.Status.scheduled.rawValue)

        let fired = try #require(db.reminderSync(accountId: 1, postServerId: 4, rootCommentServerId: 0, kind: "time"))
        #expect(fired.status == ReminderRecord.Status.fired.rawValue)
    }

    // MARK: - unseenReminderCountSync / activeReminderKindsSync

    @Test
    func unseenReminderCountSyncCountsOnlyFiredUnseen() async throws {
        let db = try AppDatabase.inMemory()

        _ = try await db.upsertReminder(Self.makeRecord(postServerId: 1, status: .scheduled, unseen: false))
        _ = try await db.upsertReminder(Self.makeRecord(postServerId: 2, status: .fired, unseen: true))
        _ = try await db.upsertReminder(Self.makeRecord(postServerId: 3, status: .fired, unseen: false))

        #expect(db.unseenReminderCountSync(accountId: 1) == 1)
        // A different account's rows never count towards this account's badge.
        #expect(db.unseenReminderCountSync(accountId: 2) == 0)
    }

    /// "Active" is kind-specific, not a single `status` filter: a fired `time`
    /// reminder is done (one-shot) and drops out, but a fired `activity`
    /// reminder is a recurring follow that keeps polling, so it must stay
    /// "active" - regression coverage for the bug where firing an activity
    /// follow made the "When there are new comments" checkmark go stale (OFF
    /// while still notifying) with no way to remove it from the menu.
    @Test
    func activeReminderKindsSyncIsKindSpecific() async throws {
        let db = try AppDatabase.inMemory()

        _ = try await db.upsertReminder(Self.makeRecord(postServerId: 1, kind: .time, status: .scheduled))
        _ = try await db.upsertReminder(Self.makeRecord(postServerId: 1, kind: .activity, status: .scheduled))

        let live = db.activeReminderKindsSync(accountId: 1, postServerId: 1, rootCommentServerId: 0)
        #expect(live == ["time", "activity"])

        // Firing the time reminder removes it from the "active" set - a
        // one-shot time reminder that has fired has nothing left to cancel.
        let timeReminder = try #require(db.reminderSync(accountId: 1, postServerId: 1, rootCommentServerId: 0, kind: "time"))
        try await db.markReminderFired(id: #require(timeReminder.id), firedAt: Date())

        let liveAfterTimeFires = db.activeReminderKindsSync(accountId: 1, postServerId: 1, rootCommentServerId: 0)
        #expect(liveAfterTimeFires == ["activity"])

        // Firing (and re-arming, as the poll does) the activity reminder must
        // NOT remove it from the "active" set - it's still live and polling.
        let activityReminder = try #require(db.reminderSync(accountId: 1, postServerId: 1, rootCommentServerId: 0, kind: "activity"))
        try await db.rearmActivityReminder(
            id: #require(activityReminder.id),
            baselineCount: 5,
            baselineAt: Date(),
            nextCheckAt: Date().addingTimeInterval(300),
            firedAt: Date()
        )

        let liveAfterActivityFires = db.activeReminderKindsSync(accountId: 1, postServerId: 1, rootCommentServerId: 0)
        #expect(liveAfterActivityFires == ["activity"])
    }

    // MARK: - Observations

    /// The Reminders segment orders fired-and-unseen rows before everything
    /// else, and within the remainder, soonest-`fireAt` first.
    @Test
    func observeReminderListOrdersFiredUnseenFirstThenByFireAt() async throws {
        let db = try AppDatabase.inMemory()

        _ = try await db.upsertReminder(Self.makeRecord(
            postServerId: 1, fireAt: Date(timeIntervalSince1970: 2_000_000_000), status: .scheduled, unseen: false
        ))
        _ = try await db.upsertReminder(Self.makeRecord(
            postServerId: 2, fireAt: Date(timeIntervalSince1970: 1_000_000_000), status: .scheduled, unseen: false
        ))
        _ = try await db.upsertReminder(Self.makeRecord(
            postServerId: 3, fireAt: Date(timeIntervalSince1970: 500_000_000), status: .fired, unseen: true
        ))

        var iterator = db.observeReminderList(accountId: 1).makeAsyncIterator()

        var ordered: [Int64]?
        while let rows = await iterator.next() {
            if rows.count == 3 {
                ordered = rows.map(\.postServerId)
                break
            }
        }
        let result = try #require(ordered)
        // Fired-unseen (postServerId 3) first, then scheduled soonest-fireAt first (2, then 1).
        #expect(result == [3, 2, 1])
    }

    @Test
    func observeUnseenReminderCountReflectsMarkRemindersSeen() async throws {
        let db = try AppDatabase.inMemory()

        var iterator = db.observeUnseenReminderCount(accountId: 1).makeAsyncIterator()
        let initial = await iterator.next()
        #expect(initial == 0)

        _ = try await db.upsertReminder(Self.makeRecord(status: .fired, unseen: true))

        var sawOne = false
        while let count = await iterator.next() {
            if count == 1 {
                sawOne = true
                break
            }
        }
        #expect(sawOne)

        try await db.markRemindersSeen(accountId: 1)

        var sawZero = false
        while let count = await iterator.next() {
            if count == 0 {
                sawZero = true
                break
            }
        }
        #expect(sawZero)
    }
}
