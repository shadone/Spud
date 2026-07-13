//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import SpudUtilKit
import Testing
@testable import SpudDataKit

// MARK: - Test doubles

/// A no-op `AlertServiceType` that silently discards every error. Mirrors the
/// identical private fake in `SchedulerServiceBackoffTests`/`SchedulerServiceGiveUpTests`
/// (each scheduler test file keeps its own copy - `private` at file scope).
private final class NullAlertService: AlertServiceType, @unchecked Sendable {
    func handle(_: Error, for _: AlertHandlerRequest) { }
    func image(error _: ImageLoadingError, for _: URL) { }
}

/// A `LemmyServiceType` fake for `SchedulerActivityPollTests`. Unlike the
/// backoff/give-up fakes (which only exercise the site-info sweep and trap on
/// everything else), this one meaningfully implements the two calls the
/// activity-reminder poll sweep can make:
///
/// - `fetchSiteInfo()` is a harmless no-op success, so the test doesn't have to
///   fight the SIGNED-IN site-info sweep's own "awaiting/stale" gating (which
///   also selects on `isSignedOutAccountType = 0`, the same scope the activity
///   poll sweep uses) to keep it from also calling this account - it's simply
///   safe either way.
/// - `fetchPostInfo(serverPostId:)` records the call (so the test can assert the
///   sweep's `commentCountFetcher` actually reached the right post) but performs
///   no DB write - the test pre-seeds the `post` row with the "already refreshed"
///   comment count directly, since exercising `LemmyService`'s real
///   `getPost` -> `numberOfComments` import path is out of scope here (covered by
///   `LemmyServicePostCounterHarvestTests`); this test is about the scheduler's
///   WIRING (enumerate accounts -> build the fetcher -> drive the poll), which
///   Task 2's `ReminderPollTests` doesn't cover.
/// - `fetchComments(serverPostId:sortType:)` (Task 3, the subtree branch) mirrors
///   the same no-op-recorder shape: it records the call so the test can assert
///   the subtree fetcher reached the right post, but performs no DB write - the
///   test pre-seeds the `comment` row with the "already refreshed" `childCount`
///   directly, since exercising `LemmyService`'s real `getComments` ->
///   `CommentImporter.childCount` import path is out of scope here (covered by
///   Task 1's `CommentChildCountTests`).
private actor ActivityPollLemmyService: LemmyServiceType {
    private(set) var fetchPostInfoCalls: [Int64] = []
    private(set) var fetchCommentsCalls: [Int64] = []

    func fetchSiteInfo() async throws { }

    func fetchPostInfo(serverPostId: Lemmy.PostID) async throws {
        fetchPostInfoCalls.append(Int64(serverPostId))
    }

    // MARK: - Unused protocol requirements (trap if reached)

    func getSiteInfo() async throws -> LemmyKit.SiteInfo {
        activityPollUnreachable()
    }

    func unreadCount() async throws -> UnreadCount {
        activityPollUnreachable()
    }

    func setShowNsfw(_: Bool) async throws {
        activityPollUnreachable()
    }

    func setBlurNsfw(_: Bool) async throws {
        activityPollUnreachable()
    }

    func setDefaultSortType(_: Lemmy.SortType) async throws {
        activityPollUnreachable()
    }

    func saveProfile(displayName _: String?, bio _: String?, avatar _: ProfileImageEdit, banner _: ProfileImageEdit, showScores _: Bool, showBotAccounts _: Bool, showReadPosts _: Bool, showAvatars _: Bool, defaultListingType _: Lemmy.ListingType) async throws {
        activityPollUnreachable()
    }

    func fetchPersonInfo(serverPersonId _: Lemmy.PersonID) async throws {
        activityPollUnreachable()
    }

    func fetchPersonContent(serverPersonId _: Lemmy.PersonID, sort _: Lemmy.SortType, page _: Int64) async throws -> PersonContentPage {
        activityPollUnreachable()
    }

    func fetchCommunityInfo(serverCommunityId _: Lemmy.CommunityID) async throws {
        activityPollUnreachable()
    }

    func fetchCommunityInfo(communityName _: String) async throws -> Lemmy.CommunityID {
        activityPollUnreachable()
    }

    func search(query _: String, type _: Lemmy.SearchType, sort _: Lemmy.SortType?, listingType _: Lemmy.ListingType, page _: Int64) async throws -> LemmyKit.SearchResults {
        activityPollUnreachable()
    }

    func listCommunities(type _: Lemmy.ListingType, sort _: Lemmy.SortType?, limit _: Int64?) async throws -> [Lemmy.CommunityView] {
        activityPollUnreachable()
    }

    func setSubscribed(serverCommunityId _: Lemmy.CommunityID, subscribed _: Bool) async throws {
        activityPollUnreachable()
    }

    func vote(serverPostId _: Lemmy.PostID, vote _: VoteStatus.Action) async throws {
        activityPollUnreachable()
    }

    func vote(serverCommentId _: Lemmy.CommentID, vote _: VoteStatus.Action) async throws {
        activityPollUnreachable()
    }

    func createComment(serverPostId _: Lemmy.PostID, content _: String, parentCommentId _: Lemmy.CommentID?) async throws {
        activityPollUnreachable()
    }

    func createPost(serverCommunityId _: Lemmy.CommunityID, name _: String, url _: String?, body _: String?, nsfw _: Bool) async throws -> Lemmy.PostID {
        activityPollUnreachable()
    }

    func uploadImage(imageData _: Data, fileName _: String, mimeType _: String) async throws -> URL {
        activityPollUnreachable()
    }

    func setSaved(serverPostId _: Lemmy.PostID, saved _: Bool) async throws {
        activityPollUnreachable()
    }

    func setSaved(serverCommentId _: Lemmy.CommentID, saved _: Bool) async throws {
        activityPollUnreachable()
    }

    func deleteComment(serverCommentId _: Lemmy.CommentID, deleted _: Bool) async throws {
        activityPollUnreachable()
    }

    func deletePost(serverPostId _: Lemmy.PostID, deleted _: Bool) async throws {
        activityPollUnreachable()
    }

    func hidePost(serverPostId _: Lemmy.PostID, hidden _: Bool) async throws {
        activityPollUnreachable()
    }

    func outboxFailureEvents() async -> AsyncStream<OutboxFailure> {
        AsyncStream { $0.finish() }
    }

    func drainPendingOutbox() async {
        activityPollUnreachable()
    }

    func saveDraft(_: OutboundDraftInput) async throws -> String {
        activityPollUnreachable()
    }

    func submitDraft(clientToken _: String) async {
        activityPollUnreachable()
    }

    func retryComposition(clientToken _: String) async {
        activityPollUnreachable()
    }

    func discardComposition(clientToken _: String) async {
        activityPollUnreachable()
    }

    func loadDraft(draftKey _: String) async throws -> OutboundContentRecord? {
        activityPollUnreachable()
    }

    func saveDirectMessageDraft(body _: String, recipientServerPersonId _: Int64) async throws -> String {
        activityPollUnreachable()
    }

    func sendDirectMessage(body _: String, recipientServerPersonId _: Int64) async throws -> String {
        activityPollUnreachable()
    }

    func applyOptimisticPostEdit(serverPostId _: Lemmy.PostID, title _: String, body _: String?, url _: String?, nsfw _: Bool) async {
        activityPollUnreachable()
    }

    func composerFailureEvents() async -> AsyncStream<ComposerOutboxFailure> {
        AsyncStream { $0.finish() }
    }

    func composerSuccessEvents() async -> AsyncStream<ComposerOutboxSuccess> {
        AsyncStream { $0.finish() }
    }

    func markAsRead(serverPostId _: Lemmy.PostID) async throws {
        activityPollUnreachable()
    }

    func fetchReplies(unreadOnly _: Bool, page _: Int64) async throws -> [InboxCommentNotification] {
        activityPollUnreachable()
    }

    func fetchMentions(unreadOnly _: Bool, page _: Int64) async throws -> [InboxCommentNotification] {
        activityPollUnreachable()
    }

    func fetchPrivateMessages(unreadOnly _: Bool, pageCursor _: String?) async throws -> (messages: [IncomingPrivateMessage], nextCursor: String?) {
        activityPollUnreachable()
    }

    func markInboxItemAsRead(reference _: InboxItemReadReference, read _: Bool) async throws {
        activityPollUnreachable()
    }

    func markPrivateMessageAsRead(privateMessageId _: Lemmy.PrivateMessageID, read _: Bool) async throws {
        activityPollUnreachable()
    }

    func markAllInboxAsRead() async throws {
        activityPollUnreachable()
    }

    func sendPrivateMessage(content _: String, recipientId _: Lemmy.PersonID) async throws -> Lemmy.PrivateMessageView {
        activityPollUnreachable()
    }

    func setBlocked(serverPersonId _: Lemmy.PersonID, blocked _: Bool) async throws {
        activityPollUnreachable()
    }

    func setBlocked(serverCommunityId _: Lemmy.CommunityID, blocked _: Bool) async throws {
        activityPollUnreachable()
    }

    func reportPost(serverPostId _: Lemmy.PostID, reason _: String) async throws {
        activityPollUnreachable()
    }

    func reportComment(serverCommentId _: Lemmy.CommentID, reason _: String) async throws {
        activityPollUnreachable()
    }

    func fetchBlockedList() async throws -> BlockedList {
        activityPollUnreachable()
    }

    func fetchModerationCapability() async throws -> ModerationCapability {
        activityPollUnreachable()
    }

    func removePost(serverPostId _: Lemmy.PostID, removed _: Bool, reason _: String?) async throws {
        activityPollUnreachable()
    }

    func lockPost(serverPostId _: Lemmy.PostID, locked _: Bool) async throws {
        activityPollUnreachable()
    }

    func featurePost(serverPostId _: Lemmy.PostID, featured _: Bool, local _: Bool) async throws {
        activityPollUnreachable()
    }

    func removeComment(serverCommentId _: Lemmy.CommentID, removed _: Bool, reason _: String?) async throws {
        activityPollUnreachable()
    }

    func distinguishComment(serverCommentId _: Lemmy.CommentID, distinguished _: Bool) async throws {
        activityPollUnreachable()
    }

    func banFromCommunity(serverCommunityId _: Lemmy.CommunityID, serverPersonId _: Lemmy.PersonID, ban _: Bool, removeData _: Bool, reason _: String?) async throws {
        activityPollUnreachable()
    }

    func resolveObject(query _: String) async throws -> ResolvedLemmyObject {
        activityPollUnreachable()
    }

    func fetchFeed(_: FeedHandle, pageCursor _: String?, showNsfw _: Bool) async throws -> String? {
        activityPollUnreachable()
    }

    func fetchComments(serverPostId: Lemmy.PostID, sortType _: Lemmy.CommentSortType) async throws {
        fetchCommentsCalls.append(Int64(serverPostId))
    }
}

private func activityPollUnreachable(_ function: StaticString = #function) -> Never {
    fatalError("ActivityPollLemmyService.\(function) must not be called in SchedulerActivityPollTests")
}

/// Minimal `@MainActor` fake for `AccountServiceType` that returns a single
/// shared `LemmyServiceType` and a single REAL `ReminderService` (backed by the
/// test's own in-memory `AppDatabase` + fake scheduler) for every keychainId.
/// Unlike `lemmyService`, `reminderService(forAccountKeychainId:)` on the real
/// `AccountServiceType` returns a concrete `ReminderService`, not a protocol -
/// so the cheapest fake is to construct a real one and hand it back, exactly as
/// `AccountService.reminderService(forAccountKeychainId:)` does in production.
@MainActor
private final class ActivityPollAccountService: AccountServiceType {
    let stubbedLemmyService: any LemmyServiceType
    let stubbedReminderService: ReminderService

    init(lemmyService: any LemmyServiceType, reminderService: ReminderService) {
        stubbedLemmyService = lemmyService
        stubbedReminderService = reminderService
    }

    func lemmyService(forAccountKeychainId _: String) -> any LemmyServiceType {
        stubbedLemmyService
    }

    func reminderService(forAccountKeychainId _: String) -> ReminderService {
        stubbedReminderService
    }

    func instanceActorId(forAccountKeychainId _: String) -> InstanceActorId? {
        InstanceActorId(from: "https://activity-poll-test.example.com")
    }

    func instanceCapabilities(forAccountKeychainId _: String) -> InstanceCapabilities {
        .allAvailable
    }

    func accountForSignedOut(forInstance _: InstanceActorId, isServiceAccount _: Bool) -> String {
        ""
    }

    func isSignedOut(forAccountKeychainId _: String) -> Bool {
        false
    }

    func signInAsSignedOut(atInstance _: InstanceActorId) { }
    #if DEBUG
    func seedSignedInDefaultAccount(atInstance _: InstanceActorId) { }
    #endif
    func login(atInstance _: InstanceActorId, username _: String, password _: String, totp2faToken _: String?) async throws { }
    func register(atInstance _: InstanceActorId, username _: String, email _: String?, password _: String, passwordVerify _: String, showNsfw _: Bool, captchaUuid _: String?, captchaAnswer _: String?, answer _: String?) async throws -> AccountServiceRegisterResult {
        .loggedIn
    }

    func passwordReset(atInstance _: InstanceActorId, email _: String) async throws { }
    func logout(forAccountKeychainId _: String) { }
    func removeAccount(forAccountKeychainId _: String) { }
    func currentDefaultAccountKeychainId() -> String? {
        nil
    }

    func setDefaultAccount(forAccountKeychainId _: String) { }
    func accountKeychainId(forInstance _: InstanceActorId) -> String {
        ""
    }

    func defaultListingType(forAccountKeychainId _: String) -> Lemmy.ListingType {
        .All
    }

    func defaultSortType(forAccountKeychainId _: String) -> Lemmy.SortType {
        .Hot
    }

    func setDefaultSortType(_: Lemmy.SortType, forAccountKeychainId _: String) { }
    func refreshSiteInfoOnDemandIfNeeded(forAccountKeychainId _: String) { }
    func scope(forAccountKeychainId _: String) -> AccountScope {
        fatalError("not used in SchedulerActivityPollTests")
    }
}

// MARK: - ActivityPollClockBox

/// A reference-type clock wrapper so the `@Sendable` `now` closure can capture
/// a mutable date without triggering a Swift 6 data-race diagnostic. Both the
/// closure (called from `@MainActor` SchedulerService) and the test's reads run
/// on `@MainActor`, so concurrent access never occurs.
private final class ActivityPollClockBox: @unchecked Sendable {
    var date: Date
    init(_ date: Date) {
        self.date = date
    }
}

// MARK: - SchedulerActivityPollTests

/// Verifies the Task 3 wiring: `SchedulerService.tick()` enumerates pollable
/// accounts (BOTH signed-in and signed-out, via `pollableAccountKeychainIds()`),
/// builds each account's `commentCountFetcher` from its `LemmyService` +
/// `postNumberOfCommentsSync`, and drives `ReminderService.pollDueActivityReminders`
/// once per account - resulting in a due activity reminder firing when the
/// (pre-seeded) live comment count clears the smart rule. `ReminderPollTests`
/// (Task 2) already exhaustively covers the poll's own fire/no-fire rule; this
/// test is only about the scheduler reaching it correctly, for both account
/// types.
///
/// The suite is `@MainActor` (`SchedulerService` is `@MainActor`) and
/// serialized because the fake `AccountService` is also `@MainActor` -
/// mirrors `SchedulerServiceBackoffTests`/`SchedulerServiceGiveUpTests`.
@MainActor
@Suite(.serialized)
struct SchedulerActivityPollTests {
    /// `nonisolated` so it can be referenced from the `@Sendable` GRDB write
    /// closure in `seedGraph` - a plain `static let` on this `@MainActor`
    /// struct would otherwise inherit main-actor isolation and fail to
    /// type-check there.
    private nonisolated static let postServerId: Int64 = 100

    /// Seeds an already-synced account (`localAccountId` set for a signed-in
    /// account, `updatedAt` = real now) plus a community and a post whose
    /// `numberOfComments` is pre-set to `postCommentCount` - i.e. the value
    /// `fetchPostInfo` would have refreshed it to, since the fake's
    /// `fetchPostInfo` is a no-op recorder rather than a real importer. Returns
    /// the account row id `ReminderService`/`ReminderRecord` key off.
    ///
    /// - Parameter isSignedOut: when `true`, seeds `isSignedOutAccountType = 1`
    ///   with no `localAccountId` (signed-out accounts never have `MyUserInfo`) -
    ///   used by `tickPollsDueActivityReminderForSignedOutAccount` to prove the
    ///   sweep's `pollableAccountKeychainIds()` scope (both account types, not
    ///   just signed-in) actually reaches a signed-out browsing account.
    private func seedGraph(
        _ appDatabase: AppDatabase,
        keychainId: String,
        postCommentCount: Int64,
        isSignedOut: Bool = false
    ) async throws -> Int64 {
        try await appDatabase.writer.write { db in
            try db.execute(
                sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)",
                arguments: ["https://activity-poll-test.example.com", Date()]
            )
            let instanceId = db.lastInsertedRowID
            try db.execute(
                sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)",
                arguments: [instanceId, Date(), Date()]
            )
            let siteId = db.lastInsertedRowID
            try db.execute(sql: """
                    INSERT INTO person (siteId, personId, name, isAdmin, isBanned, isBotAccount, isDeleted, isLocal, numberOfPosts, numberOfComments, createdAt, updatedAt)
                    VALUES (?, 10, 'alice', 0, 0, 0, 0, 0, 0, 0, ?, ?)
                """, arguments: [siteId, Date(), Date()])
            let personId = db.lastInsertedRowID
            // `localAccountId` non-nil (signed-in only) + `updatedAt` = real now
            // (NOT the test's fictional clock) so the SIGNED-IN site-info sweep -
            // which runs right before the activity-reminder sweep inside `tick()`
            // and selects on `isSignedOutAccountType = 0` - sees a signed-in
            // account here as neither "awaiting" (`localAccountId IS NULL`) nor
            // "stale" (`updatedAt` older than a day) and leaves it alone. Not
            // load-bearing for correctness (the fake's `fetchSiteInfo()` is a
            // harmless no-op either way) but keeps the test from depending on
            // that unrelated sweep's behavior at all. A signed-out account is
            // untouched by that sweep regardless (it filters on
            // `isSignedOutAccountType = 0`), so `localAccountId` is simply nil.
            let localAccountId: Int64? = isSignedOut ? nil : personId
            try db.execute(sql: """
                    INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, localAccountId, createdAt, updatedAt)
                    VALUES (?, ?, 1, 0, ?, ?, ?, ?)
                """, arguments: [siteId, keychainId, isSignedOut ? 1 : 0, localAccountId, Date(), Date()])
            let accountId = db.lastInsertedRowID
            try db.execute(sql: """
                    INSERT INTO community (accountId, communityId, name, actorId, isHidden, isLocal, isNsfw, isPostingRestrictedToMods, isRemoved, subscribedState, numberOfSubscribers, numberOfPosts, numberOfComments, createdAt, updatedAt)
                    VALUES (?, 5, 'news', 'https://activity-poll-test.example.com/c/news', 0, 0, 0, 0, 0, 'NotSubscribed', 0, 0, 0, ?, ?)
                """, arguments: [accountId, Date(), Date()])
            let communityId = db.lastInsertedRowID
            try db.execute(sql: """
                    INSERT INTO post (accountId, communityId, creatorId, postId, title, originalPostUrl, score, numberOfUpvotes, numberOfDownvotes, numberOfComments, isRead, isSaved, isHidden, isRemoved, isLocked, isFeaturedCommunity, isFeaturedLocal, isDeleted, published, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, 'A great thread', 'https://activity-poll-test.example.com/post/100', 0, 0, 0, ?, 0, 0, 0, 0, 0, 0, 0, 0, ?, ?, ?)
                """, arguments: [accountId, communityId, personId, Self.postServerId, postCommentCount, Date(), Date(), Date()])
            return accountId
        }
    }

    /// Seeds a `comment` row anchored to `seedGraph`'s post, with `childCount`
    /// pre-set to the value a real `fetchComments` + `CommentImporter` would
    /// have refreshed it to - the subtree counterpart of `seedGraph`'s
    /// `postCommentCount` parameter (which models `fetchPostInfo` having
    /// already run). `rootCommentServerId` is the comment's server id
    /// (`localCommentId`), the same value a subtree `ReminderRecord` carries.
    private func seedCommentRow(
        _ appDatabase: AppDatabase,
        accountId: Int64,
        rootCommentServerId: Int64,
        childCount: Int64
    ) async throws {
        try await appDatabase.writer.write { db in
            let postId = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM post WHERE accountId = ? AND postId = ?",
                arguments: [accountId, Self.postServerId]
            )!
            let creatorId = try Int64.fetchOne(db, sql: "SELECT id FROM person LIMIT 1")!
            try db.execute(sql: """
                    INSERT INTO comment (postId, creatorId, localCommentId, body, published, createdAt, updatedAt, childCount)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [postId, creatorId, rootCommentServerId, "root comment body", Date(), Date(), Date(), childCount])
        }
    }

    @Test
    func tickPollsDueActivityReminderAndFiresOnHigherCommentCount() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let keychainId = "kc-activity-poll"

        // The post's live comment count is already 16 by the time the poll
        // reads it back - modelling `fetchPostInfo` having refreshed it - while
        // the reminder's baseline is 10: 6 new, over the threshold of 5.
        let accountId = try await seedGraph(appDatabase, keychainId: keychainId, postCommentCount: 16)

        let clock = ActivityPollClockBox(Date(timeIntervalSince1970: 1_800_000_000))
        let reminderRecord = ReminderRecord(
            accountId: accountId,
            postServerId: Self.postServerId,
            apId: "https://activity-poll-test.example.com/post/100",
            kind: ReminderRecord.Kind.activity.rawValue,
            nextCheckAt: clock.date.addingTimeInterval(-60), // due
            baselineCount: 10,
            baselineAt: clock.date.addingTimeInterval(-3600),
            status: ReminderRecord.Status.scheduled.rawValue,
            titleSnapshot: "A great thread",
            communityName: "news",
            instanceHost: "activity-poll-test.example.com"
        )
        _ = try await appDatabase.upsertReminder(reminderRecord)

        let notificationScheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let reminderService = ReminderService(
            accountId: accountId,
            appDatabase: appDatabase,
            scheduler: notificationScheduler
        )
        let lemmyService = ActivityPollLemmyService()
        let accountService = ActivityPollAccountService(lemmyService: lemmyService, reminderService: reminderService)
        let diagnostics = DiagnosticLogSpy()

        let scheduler = SchedulerService(
            appDatabase: appDatabase,
            accountService: accountService,
            alertService: NullAlertService(),
            diagnostics: diagnostics,
            now: { clock.date },
            reachabilityMonitor: StaticReachabilityMonitor(isOnline: true)
        )

        await scheduler.tick()

        // The sweep reached the right post through the right account: the
        // fetcher's `fetchPostInfo` call landed on `postServerId`.
        let fetchCalls = await lemmyService.fetchPostInfoCalls
        #expect(fetchCalls == [Self.postServerId])

        // The poll fired: an immediate notification was posted...
        let postNowCalls = await notificationScheduler.postNowCalls
        #expect(postNowCalls.count == 1)

        // ...and the row was re-armed to `fired`/`unseen` with the baseline
        // reset to the just-observed count.
        let stored = appDatabase.reminderSync(
            accountId: accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.activity.rawValue
        )
        #expect(stored?.status == ReminderRecord.Status.fired.rawValue)
        #expect(stored?.unseen == true)
        #expect(stored?.baselineCount == 16)

        // The sweep emitted its diagnostic bookends, with the polled-account
        // count in the finish metadata.
        #expect(diagnostics.events(matching: "poll.sweep.start").count == 1)
        let finishEvents = diagnostics.events(matching: "poll.sweep.finish")
        #expect(finishEvents.count == 1)
        #expect(finishEvents.first?.metadata?["accountCount"] == "1")
    }

    /// A SIGNED-OUT account's due activity reminder is still polled - the
    /// review fix this test guards against: the sweep used to enumerate only
    /// `signedInAccountKeychainIds()`, so a reminder set while browsing
    /// signed out (Lemmy's `getPost` is anonymous, and Phase-1 TIME reminders
    /// already work signed-out) would silently never poll. Otherwise identical
    /// to `tickPollsDueActivityReminderAndFiresOnHigherCommentCount` - only
    /// `seedGraph(isSignedOut: true)` differs.
    @Test
    func tickPollsDueActivityReminderForSignedOutAccount() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let keychainId = "kc-activity-poll-signed-out"

        let accountId = try await seedGraph(
            appDatabase,
            keychainId: keychainId,
            postCommentCount: 16,
            isSignedOut: true
        )

        let clock = ActivityPollClockBox(Date(timeIntervalSince1970: 1_800_000_000))
        let reminderRecord = ReminderRecord(
            accountId: accountId,
            postServerId: Self.postServerId,
            apId: "https://activity-poll-test.example.com/post/100",
            kind: ReminderRecord.Kind.activity.rawValue,
            nextCheckAt: clock.date.addingTimeInterval(-60), // due
            baselineCount: 10,
            baselineAt: clock.date.addingTimeInterval(-3600),
            status: ReminderRecord.Status.scheduled.rawValue,
            titleSnapshot: "A great thread",
            communityName: "news",
            instanceHost: "activity-poll-test.example.com"
        )
        _ = try await appDatabase.upsertReminder(reminderRecord)

        let notificationScheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let reminderService = ReminderService(
            accountId: accountId,
            appDatabase: appDatabase,
            scheduler: notificationScheduler
        )
        let lemmyService = ActivityPollLemmyService()
        let accountService = ActivityPollAccountService(lemmyService: lemmyService, reminderService: reminderService)

        let scheduler = SchedulerService(
            appDatabase: appDatabase,
            accountService: accountService,
            alertService: NullAlertService(),
            diagnostics: DiagnosticLogSpy(),
            now: { clock.date },
            reachabilityMonitor: StaticReachabilityMonitor(isOnline: true)
        )

        await scheduler.tick()

        // The sweep reached the signed-out account's post: the fetcher's
        // `fetchPostInfo` call landed on `postServerId`.
        let fetchCalls = await lemmyService.fetchPostInfoCalls
        #expect(fetchCalls == [Self.postServerId])

        // The poll fired exactly as it would for a signed-in account.
        let postNowCalls = await notificationScheduler.postNowCalls
        #expect(postNowCalls.count == 1)

        let stored = appDatabase.reminderSync(
            accountId: accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel,
            kind: ReminderRecord.Kind.activity.rawValue
        )
        #expect(stored?.status == ReminderRecord.Status.fired.rawValue)
        #expect(stored?.unseen == true)
        #expect(stored?.baselineCount == 16)
    }

    /// Task 3: a due SUBTREE activity reminder (`rootCommentServerId != wholePostSentinel`)
    /// takes the fetcher's other branch - `fetchComments` (not `fetchPostInfo`)
    /// and `commentChildCountSync` (not `postNumberOfCommentsSync`) - and fires
    /// on the root comment's higher `child_count`, independently of the
    /// whole-post branch exercised by `tickPollsDueActivityReminderAndFiresOnHigherCommentCount`.
    @Test
    func tickPollsDueSubtreeActivityReminderAndFiresOnHigherChildCount() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let keychainId = "kc-activity-poll-subtree"
        let rootCommentServerId: Int64 = 42

        // The post itself has no whole-post follow, so its `numberOfComments`
        // is irrelevant here - only the root comment's `childCount` is read.
        let accountId = try await seedGraph(appDatabase, keychainId: keychainId, postCommentCount: 0)

        // The root comment's live `childCount` is already 9 by the time the
        // poll reads it back - modelling `fetchComments` having refreshed it -
        // while the reminder's baseline is 3: 6 new, over the threshold of 5.
        try await seedCommentRow(appDatabase, accountId: accountId, rootCommentServerId: rootCommentServerId, childCount: 9)

        let clock = ActivityPollClockBox(Date(timeIntervalSince1970: 1_800_000_000))
        let reminderRecord = ReminderRecord(
            accountId: accountId,
            postServerId: Self.postServerId,
            apId: "https://activity-poll-test.example.com/comment/\(rootCommentServerId)",
            rootCommentServerId: rootCommentServerId,
            kind: ReminderRecord.Kind.activity.rawValue,
            nextCheckAt: clock.date.addingTimeInterval(-60), // due
            baselineCount: 3,
            baselineAt: clock.date.addingTimeInterval(-3600),
            status: ReminderRecord.Status.scheduled.rawValue,
            titleSnapshot: "A great thread",
            communityName: "news",
            instanceHost: "activity-poll-test.example.com"
        )
        _ = try await appDatabase.upsertReminder(reminderRecord)

        let notificationScheduler = ReminderServiceTests.FakeReminderNotificationScheduler()
        let reminderService = ReminderService(
            accountId: accountId,
            appDatabase: appDatabase,
            scheduler: notificationScheduler
        )
        let lemmyService = ActivityPollLemmyService()
        let accountService = ActivityPollAccountService(lemmyService: lemmyService, reminderService: reminderService)
        let diagnostics = DiagnosticLogSpy()

        let scheduler = SchedulerService(
            appDatabase: appDatabase,
            accountService: accountService,
            alertService: NullAlertService(),
            diagnostics: diagnostics,
            now: { clock.date },
            reachabilityMonitor: StaticReachabilityMonitor(isOnline: true)
        )

        await scheduler.tick()

        // The sweep took the subtree branch: `fetchComments` was called (on
        // the post the comment lives under), and `fetchPostInfo` was NOT.
        let fetchCommentsCalls = await lemmyService.fetchCommentsCalls
        #expect(fetchCommentsCalls == [Self.postServerId])
        let fetchPostInfoCalls = await lemmyService.fetchPostInfoCalls
        #expect(fetchPostInfoCalls.isEmpty)

        // The poll fired: an immediate notification was posted...
        let postNowCalls = await notificationScheduler.postNowCalls
        #expect(postNowCalls.count == 1)

        // ...and the SUBTREE row was re-armed to `fired`/`unseen` with the
        // baseline reset to the just-observed `childCount`.
        let stored = appDatabase.reminderSync(
            accountId: accountId,
            postServerId: Self.postServerId,
            rootCommentServerId: rootCommentServerId,
            kind: ReminderRecord.Kind.activity.rawValue
        )
        #expect(stored?.status == ReminderRecord.Status.fired.rawValue)
        #expect(stored?.unseen == true)
        #expect(stored?.baselineCount == 9)
    }
}
