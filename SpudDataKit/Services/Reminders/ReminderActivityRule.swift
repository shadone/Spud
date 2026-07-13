//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The fixed "notify me as the discussion grows" fire rule for a whole-post
/// activity reminder (spec §3). There are no user-facing knobs - the
/// threshold, fallback interval, and poll cadence are constants owned here so
/// both the foreground poll (`ReminderService.pollDueActivityReminders`,
/// Task 2) and the "When there are new comments" menu (`Spud`, Task 4) share
/// a single source of truth.
public enum ReminderActivityRule {
    /// Fire once at least this many new comments have landed since the
    /// reminder's baseline, regardless of elapsed time.
    public static let newCommentThreshold = 5

    /// Fire once at least one new comment has landed AND this much time has
    /// elapsed since the baseline, even if the threshold hasn't been reached -
    /// so a slow-but-active thread still surfaces eventually rather than
    /// waiting indefinitely for a burst of five.
    public static let fallbackInterval: TimeInterval = 24 * 60 * 60

    /// How often a followed post's comment count is re-checked by the poll.
    /// `ReminderService.setActivityReminder`/`pollDueActivityReminders` push
    /// `nextCheckAt` forward by this amount on every check (fired or not) -
    /// centralizing the throttle here keeps every write site in agreement.
    public static let pollInterval: TimeInterval = 30 * 60

    /// Whether an activity reminder should fire, given how many new comments
    /// have landed since its baseline and how long it's been since that
    /// baseline was set (or last re-armed).
    ///
    /// Fires when `newComments >= newCommentThreshold`, OR
    /// (`newComments >= 1 AND elapsed >= fallbackInterval`). Zero new comments
    /// never fires, no matter how much time has elapsed - there's nothing new
    /// to notify about.
    public static func shouldFire(newComments: Int, elapsed: TimeInterval) -> Bool {
        guard newComments >= 1 else { return false }
        return newComments >= newCommentThreshold || elapsed >= fallbackInterval
    }
}
