//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

private let logger = Logger.reminders

/// Per-account actor owning the "remind me later" reminder lifecycle: it
/// composes the durable `reminder` table writes (`ReminderWrites.swift`) with
/// an injected `ReminderNotificationScheduling` to keep the OS local
/// notification in lock-step with the row. The Inbox "Reminders" segment and
/// the "Remind Me…" menu (Task 6/7) are the only production callers.
///
/// Phase 1 sets/removes whole-post `time` reminders
/// (`ReminderRecord.wholePostSentinel` / `Kind.time`). Phase 2 adds whole-post
/// `activity` reminders ("notify me as the discussion grows") on this same
/// actor. Phase 3 generalizes both kinds to an optional comment-subtree
/// target via `rootCommentServerId` (defaulted to `wholePostSentinel` so
/// every Phase-1/2 call site keeps compiling unchanged) - a post can carry a
/// whole-post reminder AND independent subtree reminders at once, each keyed
/// by `(accountId, postServerId, rootCommentServerId, kind)`.
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

    /// Structured diagnostics for the activity poll (`poll.fired`,
    /// `poll.fetchFailed` - spec §5.3). `diagnostics: nil` (the default) wires
    /// a real `DiagnosticLog` against the same `appDatabase` this actor
    /// already holds, so production call sites (`AccountService.
    /// reminderService(forAccountKeychainId:)`) get working diagnostics with
    /// no extra plumbing; tests that want to assert on emitted events inject a
    /// spy explicitly.
    private let diagnostics: DiagnosticLogging

    public init(
        accountId: Int64,
        appDatabase: AppDatabase,
        scheduler: ReminderNotificationScheduling,
        notificationsEnabled: @escaping @Sendable () -> Bool = { true },
        diagnostics: DiagnosticLogging? = nil
    ) {
        self.accountId = accountId
        self.appDatabase = appDatabase
        self.scheduler = scheduler
        self.notificationsEnabled = notificationsEnabled
        self.diagnostics = diagnostics ?? DiagnosticLog(appDatabase: appDatabase)
    }

    /// The stable `notificationRequestId` for a time reminder on
    /// `postServerId` (whole-post, or a comment subtree when
    /// `rootCommentServerId` is not `wholePostSentinel`) under this account -
    /// stable across repeated set/cancel/re-set cycles so `scheduler.schedule`
    /// naturally replaces any still-pending request for the same target
    /// (matches `UNUserNotificationCenter.add`'s identifier-replaces
    /// semantics). Including `rootCommentServerId` means a whole-post and a
    /// subtree reminder on the same post get distinct OS notification ids, so
    /// setting/cancelling one never touches the other.
    private func notificationRequestId(forPostServerId postServerId: Int64, rootCommentServerId: Int64) -> String {
        "reminder-\(accountId)-\(postServerId)-\(rootCommentServerId)-\(ReminderRecord.Kind.time.rawValue)"
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
    ///   - rootCommentServerId: `ReminderRecord.wholePostSentinel` (the
    ///     default) for a whole-post reminder, or a comment's server id to
    ///     scope this reminder to that comment's subtree (Phase 3). Part of
    ///     the unique key, so a whole-post reminder and one or more subtree
    ///     reminders coexist independently on the same post.
    public func setTimeReminder(
        postServerId: Int64,
        apId: String,
        fireAt: Date,
        titleSnapshot: String,
        communityName: String,
        instanceHost: String,
        thumbnailUrl: String?,
        rootCommentServerId: Int64 = ReminderRecord.wholePostSentinel
    ) async throws {
        let requestId = notificationRequestId(forPostServerId: postServerId, rootCommentServerId: rootCommentServerId)

        let record = ReminderRecord(
            accountId: accountId,
            postServerId: postServerId,
            apId: apId,
            rootCommentServerId: rootCommentServerId,
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

    /// Removes the time reminder on `postServerId` (whole-post, or a comment
    /// subtree when `rootCommentServerId` is not `wholePostSentinel`), if any,
    /// and cancels its OS notification request. A no-op (not a throw) if no
    /// such reminder exists, so the "Remind Me…" menu's "Cancel reminder"
    /// action can call it unconditionally. Scoped by `rootCommentServerId` -
    /// removing a subtree reminder never touches a whole-post reminder on the
    /// same post, or a subtree reminder on a different comment.
    public func removeTimeReminder(
        postServerId: Int64,
        rootCommentServerId: Int64 = ReminderRecord.wholePostSentinel
    ) async throws {
        guard let requestId = try await appDatabase.removeReminder(
            accountId: accountId,
            postServerId: postServerId,
            rootCommentServerId: rootCommentServerId,
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
    ///   - rootCommentServerId: `ReminderRecord.wholePostSentinel` (the
    ///     default) for a whole-post follow, or a comment's server id to
    ///     scope this follow to that comment's subtree (Phase 3) - `baselineCount`
    ///     is then the comment's `child_count` (descendant count), and the
    ///     poll (`pollDueActivityReminders`) re-reads it via the fetcher's
    ///     subtree branch instead of the post's `numberOfComments`.
    public func setActivityReminder(
        postServerId: Int64,
        apId: String,
        baselineCount: Int64,
        titleSnapshot: String,
        communityName: String,
        instanceHost: String,
        thumbnailUrl: String?,
        rootCommentServerId: Int64 = ReminderRecord.wholePostSentinel
    ) async throws {
        let now = Date()
        let record = ReminderRecord(
            accountId: accountId,
            postServerId: postServerId,
            apId: apId,
            rootCommentServerId: rootCommentServerId,
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

    /// Removes the activity reminder on `postServerId` (whole-post, or a
    /// comment subtree when `rootCommentServerId` is not `wholePostSentinel`),
    /// if any. Unlike `removeTimeReminder`, there is no OS notification
    /// request to cancel - activity reminders never carry a
    /// `notificationRequestId` (`setActivityReminder` always persists it
    /// `nil`). A no-op (not a throw) if no such reminder exists, so the "When
    /// there are new comments" menu item can call it unconditionally on
    /// toggle-off.
    public func removeActivityReminder(
        postServerId: Int64,
        rootCommentServerId: Int64 = ReminderRecord.wholePostSentinel
    ) async throws {
        try await appDatabase.removeReminder(
            accountId: accountId,
            postServerId: postServerId,
            rootCommentServerId: rootCommentServerId,
            kind: ReminderRecord.Kind.activity.rawValue
        )
    }

    /// The stable `notificationRequestId` an activity reminder's ad-hoc fire
    /// posts under. Unlike ``notificationRequestId(forPostServerId:rootCommentServerId:)``
    /// this is never persisted on the row (`setActivityReminder` always
    /// writes `notificationRequestId = nil` - there's no single pending OS
    /// request to track, the poll posts a fresh one each time it fires) - it
    /// only needs to be stable enough that back-to-back fires for the same
    /// target replace rather than pile up in Notification Center. Including
    /// `rootCommentServerId` keeps a whole-post follow's and a subtree
    /// follow's ad-hoc posts independent, same rationale as the time-reminder
    /// id above.
    private func activityNotificationRequestId(forPostServerId postServerId: Int64, rootCommentServerId: Int64) -> String {
        "reminder-\(accountId)-\(postServerId)-\(rootCommentServerId)-\(ReminderRecord.Kind.activity.rawValue)"
    }

    /// Polls every activity reminder due for a check (`nextCheckAt <= asOf`)
    /// and applies the smart rule (spec §3): refreshes each target's comment
    /// count via `commentCountFetcher`, and either fires (posts the activity
    /// notification, re-arms the baseline, pushes `nextCheckAt` forward) or -
    /// on a fetch failure or a rule miss - just pushes `nextCheckAt` forward so
    /// the follow is retried on the next due sweep. `pollInterval`
    /// (`ReminderActivityRule`) is the single throttle both branches push by,
    /// so a follow is never checked more than once per interval regardless of
    /// how often this method is called.
    ///
    /// Never throws: a per-row DB write failure is logged and the poll moves
    /// on to the next row rather than aborting the whole sweep (this is a
    /// best-effort background poll, not a user-initiated action with someone
    /// waiting on the result).
    ///
    /// - Parameters:
    ///   - asOf: the poll's reference "now" - every timestamp this call writes
    ///     (`baselineAt`, `nextCheckAt`, `lastNotifiedAt`) derives from this,
    ///     not the real wall clock, so tests can drive the rule
    ///     deterministically.
    ///   - commentCountFetcher: resolves a target's live comment count, or nil
    ///     on failure (offline, server error, etc.) - a best-effort skip, not
    ///     a fatal error. Called with each due row's `postServerId` AND
    ///     `rootCommentServerId` so the caller can branch between the
    ///     whole-post count and a subtree's `child_count` (Phase 3) -
    ///     `@Sendable` because the production closure (`SchedulerService`) is
    ///     built on a different actor and crosses into this actor's isolation
    ///     to be awaited here; for a whole-post row it wraps
    ///     `LemmyService.fetchPostInfo` (refreshes `PostRecord.
    ///     numberOfComments`) followed by `postNumberOfCommentsSync` (reads it
    ///     back), and for a subtree row a comment-tree refresh followed by
    ///     `commentChildCountSync`.
    public func pollDueActivityReminders(
        asOf: Date,
        commentCountFetcher: @Sendable (_ postServerId: Int64, _ rootCommentServerId: Int64) async -> Int?
    ) async {
        let due = appDatabase.dueActivityRemindersSync(accountId: accountId, asOf: asOf)
        let nextCheckAt = asOf.addingTimeInterval(ReminderActivityRule.pollInterval)

        for reminder in due {
            guard let id = reminder.id else { continue }

            guard let commentsNowRaw = await commentCountFetcher(reminder.postServerId, reminder.rootCommentServerId) else {
                await bumpNextCheck(id: id, nextCheckAt: nextCheckAt)
                await diagnostics.record(
                    category: .reminder,
                    level: .notice,
                    event: "poll.fetchFailed",
                    message: "Activity reminder poll could not refresh the comment count",
                    instance: reminder.instanceHost,
                    metadata: ["postServerId": String(reminder.postServerId)]
                )
                continue
            }
            let commentsNow = Int64(commentsNowRaw)

            // `baselineCount`/`baselineAt` are only nil for a malformed row
            // (an activity reminder always sets both at creation) - fall back
            // to "no new comments yet" / "just now" rather than crashing the
            // poll on force-unwrap.
            let baselineCount = reminder.baselineCount ?? commentsNow
            let baselineAt = reminder.baselineAt ?? asOf
            let newComments = Int(commentsNow) - Int(baselineCount)
            let elapsed = asOf.timeIntervalSince(baselineAt)

            if ReminderActivityRule.shouldFire(newComments: newComments, elapsed: elapsed) {
                let content = ReminderNotificationFactory.activityReminderContent(
                    titleSnapshot: reminder.titleSnapshot,
                    communityName: reminder.communityName,
                    instanceHost: reminder.instanceHost,
                    apId: reminder.apId,
                    newCount: newComments,
                    rootCommentServerId: reminder.rootCommentServerId
                )
                await scheduler.postNow(
                    requestId: activityNotificationRequestId(
                        forPostServerId: reminder.postServerId,
                        rootCommentServerId: reminder.rootCommentServerId
                    ),
                    content: content
                )

                do {
                    try await appDatabase.rearmActivityReminder(
                        id: id,
                        baselineCount: commentsNow,
                        baselineAt: asOf,
                        nextCheckAt: nextCheckAt,
                        firedAt: asOf
                    )
                } catch {
                    logger.error("pollDueActivityReminders: rearmActivityReminder(\(id)) failed: \(String(describing: error), privacy: .public)")
                }

                await diagnostics.record(
                    category: .reminder,
                    level: .info,
                    event: "poll.fired",
                    message: "Activity reminder fired",
                    instance: reminder.instanceHost,
                    metadata: ["postServerId": String(reminder.postServerId), "newComments": String(newComments)]
                )
            } else {
                await bumpNextCheck(id: id, nextCheckAt: nextCheckAt)
            }
        }
    }

    /// Shared no-fire path for `pollDueActivityReminders`: pushes `nextCheckAt`
    /// forward without touching the baseline, logging (not throwing) on write
    /// failure so a single bad row can't abort the sweep.
    private func bumpNextCheck(id: Int64, nextCheckAt: Date) async {
        do {
            try await appDatabase.bumpActivityNextCheck(id: id, nextCheckAt: nextCheckAt)
        } catch {
            logger.error("pollDueActivityReminders: bumpActivityNextCheck(\(id)) failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Community follows

    /// Sets (or replaces) a "new posts" follow on the community
    /// `communityServerId`: notify me when the community posts something new
    /// (spec §4). Reuses the post-centric `reminder` columns to watch a
    /// community instead of a post - see `ReminderRecord`'s column-reuse doc
    /// comment for the full mapping (`postServerId` is the community's server
    /// id, `apId` is the community's actorId, `baselineAt` is the watermark:
    /// the newest post `published` seen at follow-time).
    ///
    /// Like `setActivityReminder`, this schedules **no** up-front OS trigger -
    /// a community follow fires ad-hoc from the foreground poll
    /// (`pollDueCommunityFollows`), which reads the watermark against the
    /// community's live newest-post dates and decides via
    /// `CommunityFollowRule.shouldFire`.
    ///
    /// Calling this a second time for the same community replaces the
    /// existing row in place and re-baselines its watermark to "now" - the
    /// unique key `(accountId, postServerId, rootCommentServerId, kind)` is
    /// shared with the other kinds, so a community follow never collides with
    /// a `time`/`activity` reminder that happens to target a post sharing the
    /// same numeric id as this community.
    ///
    /// - Parameters:
    ///   - communityServerId: the target community's server-assigned id.
    ///   - communityActorId: the community's canonical ActivityPub actor URL,
    ///     denormalized onto the row (column-reuse: stored in `apId`).
    ///   - name: the community's bare name (no `!`/`@`), denormalized onto the
    ///     row (column-reuse: stored in `communityName`).
    ///   - title: the community's display title, denormalized at set-time
    ///     (column-reuse: stored in `titleSnapshot`).
    ///   - instanceHost: the community's home instance host.
    ///   - iconUrl: the community's icon, if any, denormalized at set-time
    ///     (column-reuse: stored in `thumbnailUrl`).
    public func setCommunityFollow(
        communityServerId: Int64,
        communityActorId: String,
        name: String,
        title: String,
        instanceHost: String,
        iconUrl: String?
    ) async throws {
        let now = Date()
        let record = ReminderRecord(
            accountId: accountId,
            postServerId: communityServerId, // column reuse - see ReminderRecord
            apId: communityActorId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.communityPosts.rawValue,
            nextCheckAt: now.addingTimeInterval(CommunityFollowRule.pollInterval),
            baselineCount: nil,
            baselineAt: now, // the watermark
            status: ReminderRecord.Status.scheduled.rawValue,
            unseen: false,
            notificationRequestId: nil,
            titleSnapshot: title,
            communityName: name,
            instanceHost: instanceHost,
            thumbnailUrl: iconUrl
        )
        try await appDatabase.upsertReminder(record)

        // Side-effect only: primes the OS permission prompt on first use,
        // same rationale as `setActivityReminder`. The row above is already
        // persisted regardless of the outcome.
        _ = await isAuthorized()
    }

    /// Removes the "new posts" follow on the community `communityServerId`,
    /// if any. Unlike `removeTimeReminder`, there is no OS notification
    /// request to cancel - community follows never carry a
    /// `notificationRequestId` (`setCommunityFollow` always persists it
    /// `nil`), same as `removeActivityReminder`. A no-op (not a throw) if no
    /// such follow exists.
    public func removeCommunityFollow(communityServerId: Int64) async throws {
        try await appDatabase.removeReminder(
            accountId: accountId,
            postServerId: communityServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.communityPosts.rawValue
        )
    }

    /// The stable `notificationRequestId` a community follow's ad-hoc fire
    /// posts under. Never persisted on the row (mirrors
    /// `activityNotificationRequestId`) - it only needs to be stable enough
    /// that back-to-back fires for the same community replace rather than
    /// pile up in Notification Center.
    private func communityFollowNotificationRequestId(forCommunityServerId communityServerId: Int64) -> String {
        "reminder-\(accountId)-\(communityServerId)-\(ReminderRecord.wholePostSentinel)-\(ReminderRecord.Kind.communityPosts.rawValue)"
    }

    /// Polls every community follow due for a check (`nextCheckAt <= asOf`)
    /// and applies the fixed fire rule (`CommunityFollowRule`): refreshes each
    /// community's newest-post dates via `postDatesFetcher`, and either fires
    /// (posts the notification, re-arms the watermark to the newest date
    /// seen, pushes `nextCheckAt` forward) or - on a fetch failure or zero new
    /// posts - just pushes `nextCheckAt` forward so the follow is retried on
    /// the next due sweep. Mirrors `pollDueActivityReminders`'s structure and
    /// never-throws contract.
    ///
    /// - Parameters:
    ///   - asOf: the poll's reference "now" - every timestamp this call
    ///     writes (`baselineAt`, `nextCheckAt`, `lastNotifiedAt`) derives from
    ///     this, not the real wall clock, so tests can drive the rule
    ///     deterministically.
    ///   - postDatesFetcher: resolves a community's live newest-post
    ///     `published` dates (most recent page), or nil on failure (offline,
    ///     server error, or the community is muted) - a best-effort skip, not
    ///     a fatal error. Called with each due row's `communityServerId` AND
    ///     `communityActorId` (`@Sendable` for the same cross-actor reason as
    ///     `commentCountFetcher`).
    public func pollDueCommunityFollows(
        asOf: Date,
        postDatesFetcher: @Sendable (_ communityServerId: Int64, _ communityActorId: String) async -> [Date]?
    ) async {
        let due = appDatabase.dueCommunityFollowsSync(accountId: accountId, asOf: asOf)
        let nextCheckAt = asOf.addingTimeInterval(CommunityFollowRule.pollInterval)

        for follow in due {
            guard let id = follow.id else { continue }

            guard let dates = await postDatesFetcher(follow.postServerId, follow.apId) else {
                await bumpNextCheck(id: id, nextCheckAt: nextCheckAt)
                await diagnostics.record(
                    category: .reminder,
                    level: .notice,
                    event: "poll.community.fetchFailed",
                    message: "Community follow poll could not fetch newest posts (or the community is muted)",
                    instance: follow.instanceHost,
                    metadata: ["communityServerId": String(follow.postServerId)]
                )
                continue
            }

            // Malformed-row fallback mirrors the activity poll: a follow
            // always sets baselineAt at creation, so nil only means a damaged
            // row - treat everything as already-seen rather than firing on
            // the backlog.
            let watermark = follow.baselineAt ?? asOf
            let newPosts = dates.filter { $0 > watermark }.count

            if CommunityFollowRule.shouldFire(newPosts: newPosts) {
                let isSaturated = newPosts == dates.count && newPosts >= CommunityFollowRule.saturationThreshold
                let content = ReminderNotificationFactory.communityFollowContent(
                    title: follow.titleSnapshot,
                    communityName: follow.communityName,
                    instanceHost: follow.instanceHost,
                    newCount: newPosts,
                    isSaturated: isSaturated
                )
                await scheduler.postNow(
                    requestId: communityFollowNotificationRequestId(forCommunityServerId: follow.postServerId),
                    content: content
                )

                do {
                    try await appDatabase.rearmCommunityFollow(
                        id: id,
                        watermark: dates.max() ?? watermark,
                        nextCheckAt: nextCheckAt,
                        firedAt: asOf
                    )
                } catch {
                    logger.error("pollDueCommunityFollows: rearmCommunityFollow(\(id)) failed: \(String(describing: error), privacy: .public)")
                }

                await diagnostics.record(
                    category: .reminder,
                    level: .info,
                    event: "poll.community.fired",
                    message: "Community follow fired",
                    instance: follow.instanceHost,
                    metadata: ["communityServerId": String(follow.postServerId), "newPosts": String(newPosts)]
                )
            } else {
                await bumpNextCheck(id: id, nextCheckAt: nextCheckAt)
            }
        }
    }

    // MARK: - Account teardown (Phase 4)

    /// Deletes every reminder of this account (both kinds, whole-post and
    /// comment-subtree alike) and cancels each deleted time reminder's OS
    /// notification request. The account-teardown counterpart to
    /// `removeTimeReminder`/`removeActivityReminder` - called by
    /// `AccountService.logout`/`removeAccount` before the account row itself
    /// is deleted, so a logged-out or removed account never leaves an orphaned
    /// reminder row (or, worse, an orphaned OS notification that still fires
    /// for an account that no longer exists).
    ///
    /// Never throws: this runs as a best-effort side effect of tearing down an
    /// account, fire-and-forget from a synchronous `@MainActor` caller (see
    /// `AccountService`) - a DB failure here shouldn't block or crash the
    /// logout/removal flow. On failure the rows are simply left behind
    /// (orphaned, the exact condition this method exists to fix), same as
    /// before this method existed.
    public func removeAllReminders() async {
        let requestIds: [String]
        do {
            requestIds = try await appDatabase.removeAllReminders(accountId: accountId)
        } catch {
            logger.error("removeAllReminders failed: \(String(describing: error), privacy: .public)")
            return
        }
        for requestId in requestIds {
            await scheduler.cancel(requestId: requestId)
        }
    }
}
