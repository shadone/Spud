//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

/// One-shot synchronous reads over the `reminder` table - single-target
/// lookup, "Remind Me…" menu checkmarks, and the fired-unseen badge count.
/// Reactive reads (the Reminders segment list + a live badge stream) are in
/// `ReminderObservations.swift`.
public extension AppDatabase {
    /// The reminder for `(accountId, postServerId, rootCommentServerId, kind)`,
    /// in any status. Used by `ReminderService` to decide upsert-vs-fresh and
    /// by the "Remind Me…" menu to read the existing state before presenting.
    func reminderSync(
        accountId: Int64,
        postServerId: Int64,
        rootCommentServerId: Int64,
        kind: String
    ) -> ReminderRecord? {
        do {
            return try writer.read { db in
                try ReminderRecord
                    .filter(Column("accountId") == accountId)
                    .filter(Column("postServerId") == postServerId)
                    .filter(Column("rootCommentServerId") == rootCommentServerId)
                    .filter(Column("kind") == kind)
                    .fetchOne(db)
            }
        } catch {
            logger.error("reminderSync failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Kinds that still have a `scheduled` reminder on this target - drives the
    /// "Remind Me…" menu's "Cancel reminder" affordance (Phase 1 doesn't track
    /// which preset was chosen, so a live `time` reminder surfaces a single
    /// cancel action rather than per-preset checkmarks). A `fired`/`dismissed`/
    /// `failed` reminder is not "active" - there's nothing left to cancel - so
    /// it's excluded.
    func activeReminderKindsSync(
        accountId: Int64,
        postServerId: Int64,
        rootCommentServerId: Int64
    ) -> Set<String> {
        do {
            let kinds = try writer.read { db in
                try String.fetchAll(db, sql: """
                        SELECT kind FROM reminder
                        WHERE accountId = ?
                          AND postServerId = ?
                          AND rootCommentServerId = ?
                          AND status = ?
                    """, arguments: [
                    accountId, postServerId, rootCommentServerId,
                    ReminderRecord.Status.scheduled.rawValue,
                ])
            }
            return Set(kinds)
        } catch {
            logger.error("activeReminderKindsSync failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Count of fired-and-still-unseen reminders for the account - the source
    /// for the Inbox "Reminders" segment / tab badge. `markRemindersSeen`
    /// clears it back to zero once the segment is opened.
    func unseenReminderCountSync(accountId: Int64) -> Int {
        do {
            return try writer.read { db in
                try Int.fetchOne(db, sql: """
                        SELECT COUNT(*) FROM reminder WHERE accountId = ? AND status = ? AND unseen = 1
                    """, arguments: [accountId, ReminderRecord.Status.fired.rawValue]) ?? 0
            }
        } catch {
            logger.error("unseenReminderCountSync failed: \(String(describing: error), privacy: .public)")
            return 0
        }
    }
}
