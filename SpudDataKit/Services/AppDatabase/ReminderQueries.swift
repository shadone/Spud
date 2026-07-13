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

    /// Kinds still "active" on this target - drives the "Remind Me…" menu's
    /// checkmarks and "Cancel reminder" affordance. "Active" is
    /// **kind-specific**, not a single `status` filter, because `time` and
    /// `activity` diverge on what "still live" means:
    /// - `time`: active only while `.scheduled` - a one-shot reminder that has
    ///   fired is done, so it drops out (mirrors
    ///   `reconcileOverdueTimeReminders`'s scope). Phase 1 doesn't track which
    ///   preset was chosen, so a live `time` reminder surfaces a single cancel
    ///   action rather than per-preset checkmarks.
    /// - `activity`: active while `.scheduled` OR `.fired` - a fired-then-
    ///   re-armed follow keeps polling (mirrors `dueActivityRemindersSync`'s
    ///   scope), so it must stay "active" or the "When there are new comments"
    ///   checkmark would go stale (showing OFF while the user is still being
    ///   notified) and toggling it would re-baseline instead of removing it.
    ///
    /// `.dismissed`/`.failed` are never active for either kind - there's
    /// nothing left to cancel/toggle.
    func activeReminderKindsSync(
        accountId: Int64,
        postServerId: Int64,
        rootCommentServerId: Int64
    ) -> Set<String> {
        do {
            let kinds = try writer.read { db in
                try String.fetchAll(db, sql: """
                        SELECT DISTINCT kind FROM reminder
                        WHERE accountId = ?
                          AND postServerId = ?
                          AND rootCommentServerId = ?
                          AND (
                                (kind = ? AND status = ?)
                             OR (kind = ? AND status IN (?, ?))
                          )
                    """, arguments: [
                    accountId, postServerId, rootCommentServerId,
                    ReminderRecord.Kind.time.rawValue, ReminderRecord.Status.scheduled.rawValue,
                    ReminderRecord.Kind.activity.rawValue, ReminderRecord.Status.scheduled.rawValue, ReminderRecord.Status.fired.rawValue,
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

    /// Every whole-post `activity` reminder due for a poll check: `kind ==
    /// .activity`, `status` is `.scheduled` OR `.fired` (a fired-then-re-armed
    /// follow keeps polling - only `.dismissed`/`.failed` drop out), and
    /// `nextCheckAt <= asOf`. Drives `ReminderService.pollDueActivityReminders`
    /// (Task 2) - `SchedulerService`'s foreground sweep (Task 3) calls that once
    /// per account per tick.
    ///
    /// `asOf` is bound as a `Date` (not an epoch double) to match
    /// `nextCheckAt`'s ISO-8601-text storage - see the GRDB date-storage
    /// convention in the project `CLAUDE.md`; a Double-vs-text comparison would
    /// silently match nothing.
    func dueActivityRemindersSync(accountId: Int64, asOf: Date) -> [ReminderRecord] {
        do {
            return try writer.read { db in
                try ReminderRecord.fetchAll(db, sql: """
                        SELECT * FROM reminder
                        WHERE accountId = ?
                          AND kind = ?
                          AND status IN (?, ?)
                          AND nextCheckAt IS NOT NULL
                          AND nextCheckAt <= ?
                    """, arguments: [
                    accountId,
                    ReminderRecord.Kind.activity.rawValue,
                    ReminderRecord.Status.scheduled.rawValue,
                    ReminderRecord.Status.fired.rawValue,
                    asOf,
                ])
            }
        } catch {
            logger.error("dueActivityRemindersSync failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// The live `PostRecord.numberOfComments` for `(account, serverPostId)` -
    /// the canonical comment count, refreshed only by a full `PostView` import
    /// (see the project `CLAUDE.md`'s comment-count-source rule). Resolves the
    /// account from `keychainId` first, mirroring `lastOpenedAtSync`. Used by
    /// the activity-reminder poll's `commentCountFetcher` (built in
    /// `SchedulerService`, Task 3) after it refreshes the post via
    /// `LemmyService.fetchPostInfo` - declared here (Task 2) so that seam
    /// already exists when Task 3 wires it up. nil if the account or post row
    /// is unknown (e.g. the post was never fetched/cached locally).
    func postNumberOfCommentsSync(forKeychainId keychainId: String, serverPostId: Int64) -> Int? {
        do {
            return try writer.read { db -> Int? in
                guard let accountId = try Self.accountRowId(forKeychainId: keychainId, in: db) else {
                    return nil
                }
                let count: Int64? = try Int64.fetchOne(db, sql: """
                        SELECT numberOfComments FROM post WHERE accountId = ? AND postId = ?
                    """, arguments: [accountId, serverPostId])
                return count.map(Int.init)
            }
        } catch {
            logger.error("postNumberOfCommentsSync failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
