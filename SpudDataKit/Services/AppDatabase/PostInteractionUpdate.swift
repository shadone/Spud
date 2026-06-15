//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Pure, UIKit-free mutation math for `PostInteractionRecord`. Isolated from
/// storage so every counter/snapshot/retention rule is unit-tested without a
/// database.
public enum PostInteractionUpdate {
    /// Seen-only entries older than this are pruned. 30 days.
    public static let defaultSeenRetention: TimeInterval = 30 * 24 * 60 * 60
    /// Opened entries older than this are pruned. 365 days.
    public static let defaultOpenedRetention: TimeInterval = 365 * 24 * 60 * 60

    /// Applies an "opened" event. Returns the updated record and the
    /// `lastOpenedAt` value *before* this open (nil on a first-ever open) so the
    /// caller can compute the new-comment delta.
    public static func applyingOpen(
        to existing: PostInteractionRecord?,
        accountId: Int64,
        postServerId: Int64,
        now: Date,
        commentCount: Int64?,
        snapshot: PostInteractionSnapshot?
    ) -> (record: PostInteractionRecord, previousOpenedAt: Date?) {
        let previous = existing?.lastOpenedAt
        var record = existing ?? PostInteractionRecord(accountId: accountId, postServerId: postServerId)
        record.lastOpenedAt = now
        record.openedCount += 1
        if let commentCount {
            record.lastKnownCommentCount = commentCount
        }
        if let snapshot {
            record.apply(snapshot)
        }
        return (record, previous)
    }

    /// Applies a "seen on screen" event.
    public static func applyingSeen(
        to existing: PostInteractionRecord?,
        accountId: Int64,
        postServerId: Int64,
        now: Date,
        snapshot: PostInteractionSnapshot
    ) -> PostInteractionRecord {
        var record = existing ?? PostInteractionRecord(accountId: accountId, postServerId: postServerId)
        if record.firstSeenAt == nil {
            record.firstSeenAt = now
        }
        record.lastSeenAt = now
        record.seenCount += 1
        record.apply(snapshot)
        return record
    }

    /// Whether `record` should be deleted under the retention policy. Saved
    /// posts are exempt; opened entries use `openedRetention`; seen-only
    /// entries use `seenRetention`.
    public static func shouldPrune(
        _ record: PostInteractionRecord,
        now: Date,
        isSaved: Bool,
        seenRetention: TimeInterval,
        openedRetention: TimeInterval
    ) -> Bool {
        if isSaved {
            return false
        }
        if let lastOpenedAt = record.lastOpenedAt {
            return now.timeIntervalSince(lastOpenedAt) > openedRetention
        }
        guard let seenRef = record.lastSeenAt ?? record.firstSeenAt else {
            return false
        }
        return now.timeIntervalSince(seenRef) > seenRetention
    }
}
