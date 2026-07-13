//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
@testable import Spud

/// Covers `ReminderStatusText.describe(for:)` - the pure status-line text
/// shared by `InboxReminderCell`'s visible label and its VoiceOver mirror.
/// Focuses on the Phase 2 `activity`-kind branch; the pre-existing `time`-kind
/// `fired`/no-`fireAt` branches are covered too so a future edit can't
/// silently change Phase 1's behavior.
struct ReminderStatusTextTests {
    @Test
    func activityScheduledReadsWatching() {
        let row = Self.row(kind: .activity, status: .scheduled, fireAt: nil)
        #expect(ReminderStatusText.describe(for: row) == "Watching for new comments")
    }

    @Test
    func activityFiredReadsNewComments() {
        let row = Self.row(kind: .activity, status: .fired, fireAt: nil)
        #expect(ReminderStatusText.describe(for: row) == "New comments · tap to catch up")
    }

    @Test
    func timeFiredReadsTapToRevisit() {
        let row = Self.row(kind: .time, status: .fired, fireAt: nil)
        #expect(ReminderStatusText.describe(for: row) == "Tap to revisit")
    }

    @Test
    func timeScheduledWithNoFireAtIsEmpty() {
        // Defensive: a `time` reminder always carries a `fireAt`, but the
        // fallback for a malformed row should stay a blank string rather than
        // crash or fall through to the activity copy.
        let row = Self.row(kind: .time, status: .scheduled, fireAt: nil)
        #expect(ReminderStatusText.describe(for: row).isEmpty)
    }

    private static func row(
        kind: ReminderRecord.Kind,
        status: ReminderRecord.Status,
        fireAt: Date?
    ) -> ReminderListRow {
        ReminderListRow(
            id: 1,
            postServerId: 42,
            apId: "https://lemmy.world/post/42",
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: kind.rawValue,
            status: status.rawValue,
            unseen: false,
            fireAt: fireAt,
            titleSnapshot: "A scenic mountain lake at golden hour",
            communityName: "photography",
            instanceHost: "lemmy.world",
            thumbnailUrl: nil
        )
    }
}
