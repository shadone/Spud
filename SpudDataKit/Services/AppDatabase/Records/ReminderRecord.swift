//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// A durable "remind me later" reminder on a post (or, in a later phase, a
/// comment subtree), per account. This is the source of truth for reminders:
/// `ReminderService` upserts/removes rows here and drives an
/// injected `ReminderNotificationScheduling` to schedule/cancel the matching
/// OS local notification; the Inbox "Reminders" segment renders straight from
/// this table.
///
/// `apId` and the `titleSnapshot`/`communityName`/`instanceHost`/`thumbnailUrl`
/// fields are denormalized at write time (mirrors `postInteraction`/`voteEvent`)
/// so a fired reminder can be rendered and opened without the (possibly
/// evicted) `post` cache row.
///
/// `rootCommentServerId` uses the sentinel `wholePostSentinel` (0) rather than
/// `NULL` for "whole post" - SQLite treats `NULL` as distinct from every other
/// `NULL` inside a `UNIQUE` index, so two whole-post reminders on the same post
/// would not collide if the column were nullable. The sentinel makes
/// `(accountId, postServerId, rootCommentServerId, kind)` an effective
/// "one live reminder per kind per target" constraint.
///
/// `kind` is one of `"time"`, `"activity"`, or `"communityPosts"` (see `Kind`) -
/// all three are live. `nextCheckAt`/`baselineCount`/`baselineAt` were added in
/// the Phase 1 migration alongside the `time` kind, even though `activity`
/// (Phase 2) and `communityPosts` (this phase) didn't start using them until
/// later, so neither later phase needed its own migration; `communityPosts`
/// uses `nextCheckAt` and `baselineAt` (the watermark) but always leaves
/// `baselineCount` nil (see the column-reuse table below).
///
/// `kind == .communityPosts` reuses the same post-centric columns to watch a
/// *community* instead, rather than adding a migration for a parallel set of
/// community-shaped columns:
/// - `postServerId` - the community's server id (not a post id)
/// - `apId` - the community's actorId
/// - `titleSnapshot` - the community's title
/// - `thumbnailUrl` - the community's icon URL
/// - `baselineAt` - the watermark: the newest post `published` timestamp
///   observed as of the last check
/// - `baselineCount` / `fireAt` - always nil (unused by this kind)
/// - `rootCommentServerId` - always `wholePostSentinel` (0); a community
///   follow has no comment-subtree variant
public struct ReminderRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "reminder"

    public var id: Int64?
    public var accountId: Int64
    public var postServerId: Int64
    /// Denormalized post permalink; opens the reminder without the (evictable) post row.
    public var apId: String
    /// `wholePostSentinel` (0) for a whole-post reminder.
    public var rootCommentServerId: Int64
    /// Raw `Kind` string - `"time"` (Phase 1) | `"activity"` (Phase 2) |
    /// `"communityPosts"` (this phase).
    public var kind: String
    public var fireAt: Date?
    /// Activity-kind only; unused in Phase 1.
    public var nextCheckAt: Date?
    /// Activity-kind only; unused in Phase 1.
    public var baselineCount: Int64?
    /// Activity-kind only; unused in Phase 1.
    public var baselineAt: Date?
    public var lastNotifiedAt: Date?
    /// Raw `Status` string.
    public var status: String
    /// Whether a fired reminder is still unseen in the Inbox segment (drives the badge).
    public var unseen: Bool
    /// The identifier passed to `ReminderNotificationScheduling.schedule`/`cancel`, so the
    /// matching OS notification request can be cancelled when the reminder is removed.
    public var notificationRequestId: String?
    public var titleSnapshot: String
    public var communityName: String
    public var instanceHost: String
    public var thumbnailUrl: String?
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        accountId: Int64,
        postServerId: Int64,
        apId: String,
        rootCommentServerId: Int64 = ReminderRecord.wholePostSentinel,
        kind: String,
        fireAt: Date? = nil,
        nextCheckAt: Date? = nil,
        baselineCount: Int64? = nil,
        baselineAt: Date? = nil,
        lastNotifiedAt: Date? = nil,
        status: String,
        unseen: Bool = false,
        notificationRequestId: String? = nil,
        titleSnapshot: String,
        communityName: String,
        instanceHost: String,
        thumbnailUrl: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.postServerId = postServerId
        self.apId = apId
        self.rootCommentServerId = rootCommentServerId
        self.kind = kind
        self.fireAt = fireAt
        self.nextCheckAt = nextCheckAt
        self.baselineCount = baselineCount
        self.baselineAt = baselineAt
        self.lastNotifiedAt = lastNotifiedAt
        self.status = status
        self.unseen = unseen
        self.notificationRequestId = notificationRequestId
        self.titleSnapshot = titleSnapshot
        self.communityName = communityName
        self.instanceHost = instanceHost
        self.thumbnailUrl = thumbnailUrl
        self.createdAt = createdAt
    }
}

extension ReminderRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public extension ReminderRecord {
    /// `rootCommentServerId` value meaning "the whole post" (not a specific comment subtree).
    static let wholePostSentinel: Int64 = 0

    /// Typed view of the `kind` raw string.
    enum Kind: String {
        case time
        case activity
        /// A community "new posts" follow. Reuses the post-centric columns -
        /// see the type doc comment's column-reuse table.
        case communityPosts
    }

    /// Typed view of the `status` raw string.
    enum Status: String {
        case scheduled
        case fired
        case dismissed
        case failed
    }
}
