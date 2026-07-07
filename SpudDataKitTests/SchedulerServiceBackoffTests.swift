//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudUtilKit
import Testing
@testable import SpudDataKit

// MARK: - Test doubles

/// A no-op `AlertServiceType` that silently discards every error.
/// `SchedulerService` calls `alertService.handle` on fetch failure; the test
/// does not assert on those calls, so sinking them here keeps the test focused.
private final class NullAlertService: AlertServiceType, @unchecked Sendable {
    func handle(_: Error, for _: AlertHandlerRequest) { }
    func image(error _: ImageLoadingError, for _: URL) { }
}

/// A `LemmyServiceType` fake that always throws on `fetchSiteInfo()` and
/// counts every call. The counter is read by the test to verify back-off gating.
private actor FetchSiteLemmyService: LemmyServiceType {
    private(set) var fetchSiteInfoCallCount = 0

    func fetchSiteInfo() async throws {
        fetchSiteInfoCallCount += 1
        throw LemmyApiError.unknownServerError(httpStatusCode: 403, error: nil)
    }

    // MARK: - Unused protocol requirements (trap if reached)

    func getSiteInfo() async throws -> Lemmy.GetSiteResponse {
        unreachable()
    }

    func unreadCount() async throws -> UnreadCount {
        unreachable()
    }

    func setShowNsfw(_: Bool) async throws {
        unreachable()
    }

    func setBlurNsfw(_: Bool) async throws {
        unreachable()
    }

    func setDefaultSortType(_: Lemmy.SortType) async throws {
        unreachable()
    }

    func saveProfile(displayName _: String?, bio _: String?, avatar _: String?, banner _: String?, showScores _: Bool, showBotAccounts _: Bool, showReadPosts _: Bool, showAvatars _: Bool, defaultListingType _: Lemmy.ListingType) async throws {
        unreachable()
    }

    func fetchPersonInfo(serverPersonId _: Lemmy.PersonID) async throws {
        unreachable()
    }

    func fetchPersonContent(serverPersonId _: Lemmy.PersonID, sort _: Lemmy.SortType, page _: Int64) async throws -> Lemmy.GetPersonDetailsResponse {
        unreachable()
    }

    func fetchCommunityInfo(serverCommunityId _: Lemmy.CommunityID) async throws {
        unreachable()
    }

    func fetchCommunityInfo(communityName _: String) async throws -> Lemmy.CommunityID {
        unreachable()
    }

    func search(query _: String, type _: Lemmy.SearchType, sort _: Lemmy.SortType, listingType _: Lemmy.ListingType, page _: Int64) async throws -> Lemmy.SearchResponse {
        unreachable()
    }

    func listCommunities(type _: Lemmy.ListingType, sort _: Lemmy.SortType?, limit _: Int64?) async throws -> [Lemmy.CommunityView] {
        unreachable()
    }

    func setSubscribed(serverCommunityId _: Lemmy.CommunityID, subscribed _: Bool) async throws {
        unreachable()
    }

    func vote(serverPostId _: Lemmy.PostID, vote _: VoteStatus.Action) async throws {
        unreachable()
    }

    func vote(serverCommentId _: Lemmy.CommentID, vote _: VoteStatus.Action) async throws {
        unreachable()
    }

    func createComment(serverPostId _: Lemmy.PostID, content _: String, parentCommentId _: Lemmy.CommentID?) async throws {
        unreachable()
    }

    func createPost(serverCommunityId _: Lemmy.CommunityID, name _: String, url _: String?, body _: String?, nsfw _: Bool) async throws -> Lemmy.PostID {
        unreachable()
    }

    func uploadImage(imageData _: Data, fileName _: String, mimeType _: String) async throws -> URL {
        unreachable()
    }

    func setSaved(serverPostId _: Lemmy.PostID, saved _: Bool) async throws {
        unreachable()
    }

    func setSaved(serverCommentId _: Lemmy.CommentID, saved _: Bool) async throws {
        unreachable()
    }

    func deleteComment(serverCommentId _: Lemmy.CommentID, deleted _: Bool) async throws {
        unreachable()
    }

    func deletePost(serverPostId _: Lemmy.PostID, deleted _: Bool) async throws {
        unreachable()
    }

    func fetchPostInfo(serverPostId _: Lemmy.PostID) async throws {
        unreachable()
    }

    func hidePost(serverPostId _: Lemmy.PostID, hidden _: Bool) async throws {
        unreachable()
    }

    func outboxFailureEvents() async -> AsyncStream<OutboxFailure> {
        AsyncStream { $0.finish() }
    }

    func drainPendingOutbox() async {
        unreachable()
    }

    func saveDraft(_: OutboundDraftInput) async throws -> String {
        unreachable()
    }

    func submitDraft(clientToken _: String) async {
        unreachable()
    }

    func retryComposition(clientToken _: String) async {
        unreachable()
    }

    func discardComposition(clientToken _: String) async {
        unreachable()
    }

    func loadDraft(draftKey _: String) async throws -> OutboundContentRecord? {
        unreachable()
    }

    func saveDirectMessageDraft(body _: String, recipientServerPersonId _: Int64) async throws -> String {
        unreachable()
    }

    func sendDirectMessage(body _: String, recipientServerPersonId _: Int64) async throws -> String {
        unreachable()
    }

    func applyOptimisticPostEdit(serverPostId _: Lemmy.PostID, title _: String, body _: String?, url _: String?, nsfw _: Bool) async {
        unreachable()
    }

    func composerFailureEvents() async -> AsyncStream<ComposerOutboxFailure> {
        AsyncStream { $0.finish() }
    }

    func composerSuccessEvents() async -> AsyncStream<ComposerOutboxSuccess> {
        AsyncStream { $0.finish() }
    }

    func markAsRead(serverPostId _: Lemmy.PostID) async throws {
        unreachable()
    }

    func fetchReplies(unreadOnly _: Bool, page _: Int64) async throws -> Lemmy.GetRepliesResponse {
        unreachable()
    }

    func fetchMentions(unreadOnly _: Bool, page _: Int64) async throws -> Lemmy.GetPersonMentionsResponse {
        unreachable()
    }

    func fetchPrivateMessages(unreadOnly _: Bool, page _: Int64) async throws -> Lemmy.PrivateMessagesResponse {
        unreachable()
    }

    func markReplyAsRead(commentReplyId _: Lemmy.CommentReplyID, read _: Bool) async throws {
        unreachable()
    }

    func markMentionAsRead(personMentionId _: Lemmy.PersonMentionID, read _: Bool) async throws {
        unreachable()
    }

    func markPrivateMessageAsRead(privateMessageId _: Lemmy.PrivateMessageID, read _: Bool) async throws {
        unreachable()
    }

    func markAllInboxAsRead() async throws {
        unreachable()
    }

    func sendPrivateMessage(content _: String, recipientId _: Lemmy.PersonID) async throws -> Lemmy.PrivateMessageView {
        unreachable()
    }

    func setBlocked(serverPersonId _: Lemmy.PersonID, blocked _: Bool) async throws {
        unreachable()
    }

    func setBlocked(serverCommunityId _: Lemmy.CommunityID, blocked _: Bool) async throws {
        unreachable()
    }

    func reportPost(serverPostId _: Lemmy.PostID, reason _: String) async throws {
        unreachable()
    }

    func reportComment(serverCommentId _: Lemmy.CommentID, reason _: String) async throws {
        unreachable()
    }

    func fetchBlockedList() async throws -> BlockedList {
        unreachable()
    }

    func fetchModerationCapability() async throws -> ModerationCapability {
        unreachable()
    }

    func removePost(serverPostId _: Lemmy.PostID, removed _: Bool, reason _: String?) async throws {
        unreachable()
    }

    func lockPost(serverPostId _: Lemmy.PostID, locked _: Bool) async throws {
        unreachable()
    }

    func featurePost(serverPostId _: Lemmy.PostID, featured _: Bool, local _: Bool) async throws {
        unreachable()
    }

    func removeComment(serverCommentId _: Lemmy.CommentID, removed _: Bool, reason _: String?) async throws {
        unreachable()
    }

    func distinguishComment(serverCommentId _: Lemmy.CommentID, distinguished _: Bool) async throws {
        unreachable()
    }

    func banFromCommunity(serverCommunityId _: Lemmy.CommunityID, serverPersonId _: Lemmy.PersonID, ban _: Bool, removeData _: Bool, reason _: String?) async throws {
        unreachable()
    }

    func resolveObject(query _: String) async throws -> ResolvedLemmyObject {
        unreachable()
    }

    func fetchFeed(_: FeedHandle, pageCursor _: String?, showNsfw _: Bool) async throws -> String? {
        unreachable()
    }

    func fetchComments(serverPostId _: Lemmy.PostID, sortType _: Lemmy.CommentSortType) async throws {
        unreachable()
    }
}

private func unreachable(_ function: StaticString = #function) -> Never {
    fatalError("FetchSiteLemmyService.\(function) must not be called in SchedulerServiceBackoffTests")
}

/// Minimal `@MainActor` fake for `AccountServiceType` that returns a single shared
/// `LemmyServiceType` for every keychainId. All other protocol requirements trap.
@MainActor
private final class BackoffAccountService: AccountServiceType {
    let stubbedLemmyService: any LemmyServiceType

    init(lemmyService: any LemmyServiceType) {
        stubbedLemmyService = lemmyService
    }

    func lemmyService(forAccountKeychainId _: String) -> any LemmyServiceType {
        stubbedLemmyService
    }

    func instanceActorId(forAccountKeychainId _: String) -> InstanceActorId? {
        InstanceActorId(from: "https://backoff-test.example.com")
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
        fatalError("not used in SchedulerServiceBackoffTests")
    }
}

// MARK: - ClockBox

/// A reference-type clock wrapper so the `@Sendable` `now` closure can
/// capture a mutable date without triggering a Swift 6 data-race diagnostic.
/// Both the closure (called from `@MainActor` SchedulerService) and the
/// test mutations run on `@MainActor`, so concurrent access never occurs.
private final class ClockBox: @unchecked Sendable {
    var date: Date
    init(_ date: Date) {
        self.date = date
    }
}

// MARK: - SchedulerServiceBackoffTests

/// Verifies that `SchedulerService` gates `fetchSiteInfo` calls through
/// `SchedulerBackoff` and resets the back-off on a reachability reconnect.
///
/// The suite is `@MainActor` (SchedulerService is `@MainActor`) and serialized
/// because the fake AccountService is also `@MainActor`.
@MainActor
@Suite(.serialized)
struct SchedulerServiceBackoffTests {
    // MARK: - Back-off gating + reconnect reset

    @Test
    func backoff_gatesRepeatedFetchesAndResetsOnReconnect() async throws {
        // Arrange: in-memory DB seeded with one signed-in account awaiting its
        // initial MyUserInfo fetch. It appears in `signedInAccountsAwaitingMyUserInfo()`
        // because `localAccountId IS NULL` (never fetched), and the signed-in sweep
        // routes through the in-memory `SchedulerBackoff` this test exercises.
        //
        // (The signed-out sweep no longer uses `SchedulerBackoff` — it gates on the
        // persisted give-up state instead, covered by SchedulerServiceGiveUpTests /
        // SiteInfoSweepGatingTests — so this test drives the signed-in path, which is
        // the only remaining consumer of the in-memory back-off + reconnect reset.)
        let appDatabase = try AppDatabase.inMemory()
        let keychainId = "kc-backoff-test-1"
        let seedDate = Date(timeIntervalSince1970: 1_000_000)

        try await appDatabase.writer.write { db in
            try db.execute(
                sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)",
                arguments: ["https://backoff-test.example.com", seedDate]
            )
            let instanceId = db.lastInsertedRowID
            try db.execute(
                sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)",
                arguments: [instanceId, seedDate, seedDate]
            )
            let siteId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO account
                        (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                    VALUES (?, ?, 1, 0, 0, ?, ?)
                    """,
                arguments: [siteId, keychainId, seedDate, seedDate]
            )
        }

        let fakeLemmyService = FetchSiteLemmyService()
        let fakeAccountService = BackoffAccountService(lemmyService: fakeLemmyService)
        let fakeReachability = StaticReachabilityMonitor(isOnline: false)
        let clock = ClockBox(Date(timeIntervalSince1970: 2_000_000))

        let service = SchedulerService(
            appDatabase: appDatabase,
            accountService: fakeAccountService,
            alertService: NullAlertService(),
            diagnostics: DiagnosticLogSpy(),
            now: { clock.date },
            reachabilityMonitor: fakeReachability
        )

        // Subscribe to the reachability stream so step (d) exercises the real
        // reconnect path. The Timer and asyncAfter inside startService() won't
        // fire during the test (their delays are real-time based), so they don't
        // interfere with the manual tick() calls below.
        service.startService()

        // (a) First tick: no back-off entry exists → fetch is attempted.
        await service.tick()
        var count = await fakeLemmyService.fetchSiteInfoCallCount
        #expect(count == 1, "first tick should attempt the fetch")

        // (b) Immediate second tick, clock unchanged: the back-off window (5 min)
        //     has not elapsed → fetch is gated out, count stays at 1.
        await service.tick()
        count = await fakeLemmyService.fetchSiteInfoCallCount
        #expect(count == 1, "second tick with same clock should be gated by back-off")

        // (c) Advance the injected clock past the 5-minute back-off delay.
        //     The back-off window has now elapsed → fetch is attempted again.
        clock.date = clock.date.addingTimeInterval(6 * 60) // 6 minutes
        await service.tick()
        count = await fakeLemmyService.fetchSiteInfoCallCount
        #expect(count == 2, "tick after clock advance past back-off window should attempt again")

        // (d) Flip reachability to online. The reachabilityTask (started by startService())
        //     receives the transition, calls backoff.reset(), then fires tick() directly.
        //     Poll with Task.yield() so that internal Task can run to completion.
        //     Clock is unchanged from step (c); the reset means shouldAttempt returns true.
        fakeReachability.setOnline(true)
        var finalCount = await fakeLemmyService.fetchSiteInfoCallCount
        for _ in 0..<50 {
            if finalCount == 3 { break }
            await Task.yield()
            finalCount = await fakeLemmyService.fetchSiteInfoCallCount
        }
        #expect(finalCount == 3, "reconnect transition should reset back-off and fire an immediate tick")
    }
}
