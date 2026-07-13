//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Per-account actor owning the "remind me later" reminder lifecycle: it
/// composes the durable `reminder` table writes (`ReminderWrites.swift`) with
/// an injected `ReminderNotificationScheduling` to keep the OS local
/// notification in lock-step with the row. The Inbox "Reminders" segment and
/// the "Remind Me…" menu (Task 6/7) are the only production callers.
///
/// Phase 1 sets/removes whole-post `time` reminders
/// (`ReminderRecord.wholePostSentinel` / `Kind.time`). Phase 2 adds whole-post
/// `activity` reminders ("notify me as the discussion grows") on this same
/// actor; a later phase adds comment-subtree targets.
public actor ReminderService {
    private let accountId: Int64
    private let appDatabase: AppDatabase
    private let scheduler: ReminderNotificationScheduling

    /// Whether the user has reminder notifications enabled
    /// (`PreferencesService.reminderNotificationsEnabled`). A closure rather
    /// than a stored `Bool` because `PreferencesService` lives in the `Spud`
    /// app target and this actor lives in `SpudDataKit`, which must never
    /// import the app (see the project's dependency-direction rule) - a
    /// closure lets a call site above the layer boundary supply the live
    /// value without SpudDataKit knowing preferences exist. `DependencyContainer`
    /// (the app-target call site that owns `PreferencesService`) wires the real
    /// preference through to the DI seam that vends this actor per account
    /// (`AccountService`); the `{ true }` default here is used only by tests
    /// and other non-app hosts that construct `ReminderService` directly.
    private let notificationsEnabled: @Sendable () -> Bool

    public init(
        accountId: Int64,
        appDatabase: AppDatabase,
        scheduler: ReminderNotificationScheduling,
        notificationsEnabled: @escaping @Sendable () -> Bool = { true }
    ) {
        self.accountId = accountId
        self.appDatabase = appDatabase
        self.scheduler = scheduler
        self.notificationsEnabled = notificationsEnabled
    }

    /// The stable `notificationRequestId` for a whole-post time reminder on
    /// `postServerId` under this account - stable across repeated
    /// set/cancel/re-set cycles so `scheduler.schedule` naturally replaces any
    /// still-pending request for the same target (matches
    /// `UNUserNotificationCenter.add`'s identifier-replaces semantics).
    private func notificationRequestId(forPostServerId postServerId: Int64) -> String {
        "reminder-\(accountId)-\(postServerId)-\(ReminderRecord.wholePostSentinel)-\(ReminderRecord.Kind.time.rawValue)"
    }

    /// Whether the OS notification should (still) be scheduled: the user
    /// hasn't disabled reminder notifications in-app AND the OS has granted
    /// (or now grants, on this first-use prompt) authorization. Permission is
    /// requested here - lazily, on first use - rather than at launch, so the
    /// system prompt only ever appears as a direct consequence of an explicit
    /// "Remind Me…" action.
    private func isAuthorized() async -> Bool {
        guard notificationsEnabled() else { return false }
        if await scheduler.authorizationGranted() { return true }
        return await scheduler.requestAuthorization()
    }

    /// Sets (or replaces) a time reminder on the whole post `postServerId`:
    /// upserts the durable row first, then - unless notifications are
    /// disabled/denied - schedules the matching OS local notification.
    ///
    /// Calling this a second time for the same post replaces the existing
    /// reminder in place (same row, same `notificationRequestId`): the upsert
    /// updates rather than duplicates the row (unique key
    /// `(accountId, postServerId, rootCommentServerId, kind)`), and
    /// `scheduler.schedule` under the same stable id replaces any
    /// still-pending OS request for the old `fireAt`.
    ///
    /// A denied (or preference-disabled) permission never throws - the
    /// reminder still lives in-app (visible in the Inbox "Reminders" segment,
    /// and reconciled to `fired` by `reconcileOverdue` once its `fireAt`
    /// passes even with no OS notification callback to drive that), it just
    /// produces no OS notification banner.
    ///
    /// - Parameters:
    ///   - postServerId: the target post's server-assigned id.
    ///   - apId: the post's canonical ActivityPub URL, denormalized onto the
    ///     row so a fired reminder can be opened without the (possibly
    ///     evicted) local `post` cache row.
    ///   - fireAt: when the reminder should fire.
    ///   - titleSnapshot: the post's title, denormalized at set-time.
    ///   - communityName: the post's community, bare name.
    ///   - instanceHost: the community's home instance host.
    ///   - thumbnailUrl: the post's thumbnail, if any, denormalized at set-time.
    public func setTimeReminder(
        postServerId: Int64,
        apId: String,
        fireAt: Date,
        titleSnapshot: String,
        communityName: String,
        instanceHost: String,
        thumbnailUrl: String?
    ) async throws {
        let requestId = notificationRequestId(forPostServerId: postServerId)

        let record = ReminderRecord(
            accountId: accountId,
            postServerId: postServerId,
            apId: apId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.time.rawValue,
            fireAt: fireAt,
            status: ReminderRecord.Status.scheduled.rawValue,
            unseen: false,
            notificationRequestId: requestId,
            titleSnapshot: titleSnapshot,
            communityName: communityName,
            instanceHost: instanceHost,
            thumbnailUrl: thumbnailUrl
        )
        try await appDatabase.upsertReminder(record)

        guard await isAuthorized() else {
            return
        }

        let content = ReminderNotificationFactory.timeReminderContent(
            titleSnapshot: titleSnapshot,
            communityName: communityName,
            instanceHost: instanceHost,
            apId: apId
        )
        await scheduler.schedule(requestId: requestId, fireAt: fireAt, content: content)
    }

    /// Removes the whole-post time reminder on `postServerId`, if any, and
    /// cancels its OS notification request. A no-op (not a throw) if no such
    /// reminder exists, so the "Remind Me…" menu's "Cancel reminder" action
    /// can call it unconditionally.
    public func removeTimeReminder(postServerId: Int64) async throws {
        guard let requestId = try await appDatabase.removeReminder(
            accountId: accountId,
            postServerId: postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.time.rawValue
        ) else {
            return
        }
        await scheduler.cancel(requestId: requestId)
    }

    /// Marks every overdue `scheduled` time reminder of this account
    /// `fired`/`unseen` (lighting the Inbox badge). Call on launch and on
    /// foreground (mirroring the Spotlight reindex trigger points) to catch
    /// reminders whose `fireAt` passed while the app wasn't running to receive
    /// the OS notification delivery/tap.
    public func reconcileOverdue(asOf: Date) async throws {
        _ = try await appDatabase.reconcileOverdueTimeReminders(accountId: accountId, asOf: asOf)
    }

    // MARK: - Activity reminders (Phase 2)

    /// Sets (or replaces) an activity reminder on the whole post
    /// `postServerId`: "notify me as the discussion grows" (spec §3). Unlike
    /// `setTimeReminder`, this schedules **no** up-front
    /// `UNCalendarNotificationTrigger` - activity reminders fire ad-hoc from
    /// the foreground poll (`pollDueActivityReminders`, added in a later
    /// task), which reads `baselineCount`/`baselineAt` against the live
    /// comment count and decides via `ReminderActivityRule.shouldFire`.
    ///
    /// Authorization is still requested just-in-time (mirrors
    /// `setTimeReminder`, so the first "When there are new comments" tap is
    /// also the first point the OS permission prompt can appear) but its
    /// result never gates persistence here - there's no OS request to
    /// conditionally make, only a future ad-hoc post the poll will attempt
    /// once the row is due.
    ///
    /// Calling this a second time for the same post replaces the existing row
    /// in place and re-baselines it (`baselineCount`/`baselineAt` reset to the
    /// values passed here) - the unique key `(accountId, postServerId,
    /// rootCommentServerId, kind)` is shared with `setTimeReminder`, so a post
    /// can carry independent time and activity reminders at once (different
    /// `kind`), each replacing only its own row.
    ///
    /// - Parameters:
    ///   - postServerId: the target post's server-assigned id.
    ///   - apId: the post's canonical ActivityPub URL, denormalized onto the
    ///     row so a fired reminder can be opened without the (possibly
    ///     evicted) local `post` cache row.
    ///   - baselineCount: the post's comment count at the moment the follow is
    ///     set - the poll's `new = commentsNow - baselineCount`.
    ///   - titleSnapshot: the post's title, denormalized at set-time.
    ///   - communityName: the post's community, bare name.
    ///   - instanceHost: the community's home instance host.
    ///   - thumbnailUrl: the post's thumbnail, if any, denormalized at set-time.
    public func setActivityReminder(
        postServerId: Int64,
        apId: String,
        baselineCount: Int64,
        titleSnapshot: String,
        communityName: String,
        instanceHost: String,
        thumbnailUrl: String?
    ) async throws {
        let now = Date()
        let record = ReminderRecord(
            accountId: accountId,
            postServerId: postServerId,
            apId: apId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.activity.rawValue,
            nextCheckAt: now.addingTimeInterval(ReminderActivityRule.pollInterval),
            baselineCount: baselineCount,
            baselineAt: now,
            status: ReminderRecord.Status.scheduled.rawValue,
            unseen: false,
            notificationRequestId: nil,
            titleSnapshot: titleSnapshot,
            communityName: communityName,
            instanceHost: instanceHost,
            thumbnailUrl: thumbnailUrl
        )
        try await appDatabase.upsertReminder(record)

        // Side-effect only: primes the OS permission prompt on first use so a
        // later poll-fired notification isn't silently suppressed by a
        // never-asked permission. The row above is already persisted
        // regardless of the outcome.
        _ = await isAuthorized()
    }

    /// Removes the whole-post activity reminder on `postServerId`, if any.
    /// Unlike `removeTimeReminder`, there is no OS notification request to
    /// cancel - activity reminders never carry a `notificationRequestId`
    /// (`setActivityReminder` always persists it `nil`). A no-op (not a
    /// throw) if no such reminder exists, so the "When there are new
    /// comments" menu item can call it unconditionally on toggle-off.
    public func removeActivityReminder(postServerId: Int64) async throws {
        try await appDatabase.removeReminder(
            accountId: accountId,
            postServerId: postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.activity.rawValue
        )
    }
}
