//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// Durable writes over the `reminder` table. `ReminderService` (per-account
/// actor) is the sole caller in production - these are the low-level GRDB ops
/// it composes; see that type for the create/remove/reconcile orchestration
/// (upsert + OS notification scheduling, delete + OS notification cancel).
public extension AppDatabase {
    /// Upserts `record` keyed on `(accountId, postServerId, rootCommentServerId,
    /// kind)` - the same tuple the `v35_reminder` migration's `UNIQUE` index
    /// enforces (see `ReminderRecord.wholePostSentinel` for why
    /// `rootCommentServerId` is a sentinel rather than nullable). A matching row
    /// has its mutable fields replaced by `record`'s (the existing `id` and
    /// `createdAt` are preserved, so re-scheduling a reminder doesn't lose its
    /// original creation time); otherwise a new row is inserted.
    ///
    /// - Returns: The row id, so callers can derive a stable
    ///   `notificationRequestId` without a second read.
    @discardableResult
    func upsertReminder(_ record: ReminderRecord) async throws -> Int64 {
        try await writer.write { db in
            if let existing = try ReminderRecord
                .filter(Column("accountId") == record.accountId)
                .filter(Column("postServerId") == record.postServerId)
                .filter(Column("rootCommentServerId") == record.rootCommentServerId)
                .filter(Column("kind") == record.kind)
                .fetchOne(db)
            {
                var updated = record
                updated.id = existing.id
                updated.createdAt = existing.createdAt
                try updated.update(db)
                return existing.id!
            }

            var inserted = record
            inserted.id = nil
            try inserted.insert(db)
            return inserted.id!
        }
    }

    /// Deletes the reminder matching the unique key, if any.
    ///
    /// - Returns: The removed row's `notificationRequestId` (so the caller can
    ///   cancel the matching OS notification request), or nil when no row
    ///   matched.
    @discardableResult
    func removeReminder(
        accountId: Int64,
        postServerId: Int64,
        rootCommentServerId: Int64,
        kind: String
    ) async throws -> String? {
        try await writer.write { db in
            guard let existing = try ReminderRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postServerId") == postServerId)
                .filter(Column("rootCommentServerId") == rootCommentServerId)
                .filter(Column("kind") == kind)
                .fetchOne(db)
            else {
                return nil
            }
            try existing.delete(db)
            return existing.notificationRequestId
        }
    }

    /// Marks a single reminder as fired: `status = .fired`, `unseen = true`
    /// (lights the Inbox badge), `lastNotifiedAt = firedAt`. A no-op if `id`
    /// doesn't exist (e.g. the reminder was removed after the OS notification
    /// was already scheduled).
    func markReminderFired(id: Int64, firedAt: Date) async throws {
        try await writer.write { db in
            guard var record = try ReminderRecord.fetchOne(db, key: id) else {
                return
            }
            record.status = ReminderRecord.Status.fired.rawValue
            record.unseen = true
            record.lastNotifiedAt = firedAt
            try record.update(db)
        }
    }

    /// Clears `unseen` on every fired reminder of the account - called when the
    /// Inbox "Reminders" segment is opened, so the badge count drops to zero.
    /// Scheduled reminders are untouched (they have `unseen == false` already).
    func markRemindersSeen(accountId: Int64) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE reminder SET unseen = 0 WHERE accountId = ? AND status = ?",
                arguments: [accountId, ReminderRecord.Status.fired.rawValue]
            )
        }
    }

    /// Flips every overdue, still-`scheduled`, `kind == .time` reminder of the
    /// account to `fired`/`unseen`, and returns the flipped rows (post-flip
    /// state). Called on launch/foreground to reconcile reminders that fired
    /// while the app wasn't running to receive the OS notification callback.
    ///
    /// "Overdue" means `fireAt <= asOf`; `asOf` is bound as a `Date` (not an
    /// epoch double) to match the `fireAt` column's ISO-8601-text storage - see
    /// the GRDB date-storage convention in the project `CLAUDE.md`. A future
    /// `fireAt`, a non-`time` kind, or a non-`scheduled` status is left
    /// untouched.
    @discardableResult
    func reconcileOverdueTimeReminders(accountId: Int64, asOf: Date) async throws -> [ReminderRecord] {
        try await writer.write { db in
            var overdue = try ReminderRecord.fetchAll(db, sql: """
                    SELECT * FROM reminder
                    WHERE accountId = ?
                      AND kind = ?
                      AND status = ?
                      AND fireAt IS NOT NULL
                      AND fireAt <= ?
                """, arguments: [
                accountId,
                ReminderRecord.Kind.time.rawValue,
                ReminderRecord.Status.scheduled.rawValue,
                asOf,
            ])

            for index in overdue.indices {
                overdue[index].status = ReminderRecord.Status.fired.rawValue
                overdue[index].unseen = true
                overdue[index].lastNotifiedAt = asOf
                try overdue[index].update(db)
            }
            return overdue
        }
    }

    /// Fires an activity reminder from the poll (`ReminderService.
    /// pollDueActivityReminders`, Task 2): `status = .fired`, `unseen = true`
    /// (lights the Inbox badge, mirrors `markReminderFired`), `lastNotifiedAt
    /// = firedAt`, and re-arms the baseline (`baselineCount`/`baselineAt` reset
    /// to the just-observed count/time) with `nextCheckAt` pushed forward by
    /// `pollInterval` so the follow keeps polling rather than going stale. A
    /// no-op if `id` doesn't exist (e.g. removed mid-poll).
    func rearmActivityReminder(
        id: Int64,
        baselineCount: Int64,
        baselineAt: Date,
        nextCheckAt: Date,
        firedAt: Date
    ) async throws {
        try await writer.write { db in
            guard var record = try ReminderRecord.fetchOne(db, key: id) else {
                return
            }
            record.status = ReminderRecord.Status.fired.rawValue
            record.unseen = true
            record.lastNotifiedAt = firedAt
            record.baselineCount = baselineCount
            record.baselineAt = baselineAt
            record.nextCheckAt = nextCheckAt
            try record.update(db)
        }
    }

    /// Pushes an activity reminder's `nextCheckAt` forward without touching its
    /// baseline or status - the no-fire (or fetch-failed) branch of
    /// `ReminderService.pollDueActivityReminders`, so a follow that didn't
    /// trip the smart rule this round is simply re-tried on the next due poll
    /// rather than checked every tick. A no-op if `id` doesn't exist.
    func bumpActivityNextCheck(id: Int64, nextCheckAt: Date) async throws {
        try await writer.write { db in
            guard var record = try ReminderRecord.fetchOne(db, key: id) else {
                return
            }
            record.nextCheckAt = nextCheckAt
            try record.update(db)
        }
    }

    /// Fires a community follow from the poll: `status = .fired`, `unseen =
    /// true`, `lastNotifiedAt = firedAt`, watermark (`baselineAt`) re-armed to
    /// the newest post `published` observed, `nextCheckAt` pushed forward so
    /// the follow keeps watching. A no-op if `id` doesn't exist.
    func rearmCommunityFollow(id: Int64, watermark: Date, nextCheckAt: Date, firedAt: Date) async throws {
        try await writer.write { db in
            guard var record = try ReminderRecord.fetchOne(db, key: id) else { return }
            record.status = ReminderRecord.Status.fired.rawValue
            record.unseen = true
            record.lastNotifiedAt = firedAt
            record.baselineAt = watermark
            record.nextCheckAt = nextCheckAt
            try record.update(db)
        }
    }

    /// Deletes every reminder row (both kinds, whole-post and comment-subtree
    /// alike) belonging to `accountId` - the account-teardown cleanup
    /// (`ReminderService.removeAllReminders`, called from `AccountService.
    /// logout`/`removeAccount`, Phase 4). `reminder.accountId` carries no
    /// cascading foreign key (see `ReminderWritesTests`'s doc comment), so
    /// without this a removed account's reminder rows - and any OS
    /// notification request a time reminder scheduled - would silently
    /// outlive the account.
    ///
    /// - Returns: The non-nil `notificationRequestId`s among the deleted rows
    ///   (time reminders only - `setActivityReminder` always persists `nil`,
    ///   see `ReminderService`), so the caller can cancel each one's pending
    ///   OS notification request. A DB delete alone can't do that - the
    ///   request lives in Notification Center, not the row.
    @discardableResult
    func removeAllReminders(accountId: Int64) async throws -> [String] {
        try await writer.write { db in
            let rows = try ReminderRecord
                .filter(Column("accountId") == accountId)
                .fetchAll(db)
            try ReminderRecord
                .filter(Column("accountId") == accountId)
                .deleteAll(db)
            return rows.compactMap(\.notificationRequestId)
        }
    }
}
