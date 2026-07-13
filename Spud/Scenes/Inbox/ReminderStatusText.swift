//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

/// The Inbox Reminders-segment row status text for a `ReminderListRow` -
/// shared by `InboxReminderCell`'s visible status label and its VoiceOver
/// label mirror, so the two can never drift apart. Pure (no UIKit), so it's
/// unit-testable without hosting a cell.
///
/// Branches on `kind` (Phase 2 adds the `activity` branch alongside Phase 1's
/// `time` one), and - within `activity` - on whether the reminder is scoped
/// to a comment subtree rather than the whole post (Phase 3,
/// `rootCommentServerId != ReminderRecord.wholePostSentinel`):
/// - **time, whole-post**: a relative countdown to `fireAt` ("in 2 days")
///   while `scheduled`, or "Tap to revisit" once `fired`.
/// - **time, subtree**: same countdown/"Tap to revisit" wording as
///   whole-post - a plain time reminder reads the same regardless of scope,
///   it's still just "at this time, look again" (only tapping it differs -
///   it opens the post scrolled to the thread).
/// - **activity, whole-post**: "Watching for new comments" while
///   `scheduled`, or "New comments · tap to catch up" once `fired`.
/// - **activity, subtree**: "Watching a thread for new replies" while
///   `scheduled`, or "New replies · tap to catch up" once `fired` - names the
///   thread scope explicitly so a subtree follow's row is never confused with
///   a whole-post one in the same segment.
///
/// Phase 2/3 both keep this simple - the row doesn't carry a live new-count,
/// so the fired string doesn't quote a number (unlike the ad-hoc push
/// notification body, which does; see
/// `ReminderNotificationFactory.activityReminderContent`).
enum ReminderStatusText {
    static func describe(for reminder: ReminderListRow, now: Date = Date()) -> String {
        let isSubtree = reminder.rootCommentServerId != ReminderRecord.wholePostSentinel

        if reminder.kind == ReminderRecord.Kind.activity.rawValue {
            if reminder.status == ReminderRecord.Status.fired.rawValue {
                return isSubtree
                    ? NSLocalizedString(
                        "New replies · tap to catch up",
                        comment: "Inbox reminder row status: a comment-thread (subtree) activity reminder has fired"
                    )
                    : NSLocalizedString(
                        "New comments · tap to catch up",
                        comment: "Inbox reminder row status: an activity (new-comments) reminder has fired"
                    )
            }
            return isSubtree
                ? NSLocalizedString(
                    "Watching a thread for new replies",
                    comment: "Inbox reminder row status: a comment-thread (subtree) activity reminder is live"
                )
                : NSLocalizedString(
                    "Watching for new comments",
                    comment: "Inbox reminder row status: an activity (new-comments) reminder is live"
                )
        }

        guard reminder.status != ReminderRecord.Status.fired.rawValue else {
            return NSLocalizedString("Tap to revisit", comment: "Inbox reminder row status: the reminder has fired")
        }
        guard let fireAt = reminder.fireAt else { return "" }
        // Built locally rather than as a stored formatter - a plain (non
        // `@MainActor`) `static let` formatter fails Swift 6 strict
        // concurrency, and a relative countdown must be evaluated against
        // "now" on every render anyway (it can't be cached).
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: fireAt, relativeTo: now)
    }
}
