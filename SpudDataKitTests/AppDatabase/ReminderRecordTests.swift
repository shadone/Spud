//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// Round-trip + unique-constraint coverage for `ReminderRecord` against the
/// `v35_reminder` migration. `AppDatabase.inMemory()` applies every migration
/// at once, which is fine here - `reminder` is a brand-new table, not a
/// backfill. `reminder.accountId` carries no foreign key (mirrors
/// `postInteraction`'s plain-integer `postServerId`), so these tests don't
/// need to seed instance/site/account rows.
struct ReminderRecordTests {
    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    private func makeRecord(
        accountId: Int64 = 1,
        postServerId: Int64 = 100,
        rootCommentServerId: Int64 = ReminderRecord.wholePostSentinel,
        kind: ReminderRecord.Kind = .time
    ) -> ReminderRecord {
        ReminderRecord(
            accountId: accountId,
            postServerId: postServerId,
            apId: "https://example.com/post/\(postServerId)",
            rootCommentServerId: rootCommentServerId,
            kind: kind.rawValue,
            fireAt: Date(timeIntervalSince1970: 1_800_000_000),
            lastNotifiedAt: Date(timeIntervalSince1970: 1_800_000_100),
            status: ReminderRecord.Status.scheduled.rawValue,
            unseen: false,
            notificationRequestId: "reminder-\(accountId)-\(postServerId)-\(rootCommentServerId)-\(kind.rawValue)",
            titleSnapshot: "A post title",
            communityName: "news",
            instanceHost: "example.com",
            thumbnailUrl: "https://example.com/thumb.jpg",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// (a) Insert then fetch by id, and confirm every field - including the
    /// `Date` columns - survives the ISO-8601-text round trip to the second.
    @Test
    func insertingAndFetchingByIdRoundTripsEveryField() throws {
        let record = makeRecord()

        let insertedId = try appDatabase.writer.write { db -> Int64 in
            var inserted = record
            try inserted.insert(db)
            return try #require(inserted.id)
        }

        let fetched = try appDatabase.writer.read { db in
            try ReminderRecord.fetchOne(db, key: insertedId)
        }
        let unwrapped = try #require(fetched)

        #expect(unwrapped.accountId == record.accountId)
        #expect(unwrapped.postServerId == record.postServerId)
        #expect(unwrapped.apId == record.apId)
        #expect(unwrapped.rootCommentServerId == record.rootCommentServerId)
        #expect(unwrapped.kind == record.kind)
        #expect(unwrapped.status == record.status)
        #expect(unwrapped.unseen == record.unseen)
        #expect(unwrapped.notificationRequestId == record.notificationRequestId)
        #expect(unwrapped.titleSnapshot == record.titleSnapshot)
        #expect(unwrapped.communityName == record.communityName)
        #expect(unwrapped.instanceHost == record.instanceHost)
        #expect(unwrapped.thumbnailUrl == record.thumbnailUrl)
        #expect(unwrapped.nextCheckAt == record.nextCheckAt)
        #expect(unwrapped.baselineCount == record.baselineCount)
        #expect(unwrapped.baselineAt == record.baselineAt)

        let fetchedFireAt = try #require(unwrapped.fireAt)
        let expectedFireAt = try #require(record.fireAt)
        #expect(abs(fetchedFireAt.timeIntervalSince1970 - expectedFireAt.timeIntervalSince1970) < 1)

        let fetchedNotifiedAt = try #require(unwrapped.lastNotifiedAt)
        let expectedNotifiedAt = try #require(record.lastNotifiedAt)
        #expect(abs(fetchedNotifiedAt.timeIntervalSince1970 - expectedNotifiedAt.timeIntervalSince1970) < 1)

        #expect(abs(unwrapped.createdAt.timeIntervalSince1970 - record.createdAt.timeIntervalSince1970) < 1)
    }

    /// (b) Two inserts with the same `(accountId, postServerId,
    /// rootCommentServerId=0, kind="time")` - the second `insert` must throw a
    /// unique-constraint error, proving the sentinel (not `NULL`) is what makes
    /// the unique index actually collide.
    @Test
    func duplicateWholePostTimeReminderViolatesUniqueConstraint() throws {
        try appDatabase.writer.write { db in
            var first = makeRecord()
            try first.insert(db)
        }

        #expect(throws: (any Error).self) {
            try appDatabase.writer.write { db in
                var duplicate = makeRecord()
                try duplicate.insert(db)
            }
        }
    }

    /// (c) Two inserts differing only by `kind` ("time" vs "activity") both
    /// succeed - the unique key includes `kind`, so they don't collide.
    @Test
    func differingOnlyByKindBothInsertsSucceed() throws {
        try appDatabase.writer.write { db in
            var timeReminder = makeRecord(kind: .time)
            try timeReminder.insert(db)

            var activityReminder = makeRecord(kind: .activity)
            try activityReminder.insert(db)
        }

        let count = try appDatabase.writer.read { db in
            try ReminderRecord.fetchCount(db)
        }
        #expect(count == 2)
    }
}
