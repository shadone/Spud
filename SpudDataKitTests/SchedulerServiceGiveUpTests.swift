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

/// A no-op `AlertServiceType` that silently discards every error.
/// `SchedulerService` calls `alertService.handle` on fetch failure; these tests
/// do not assert on those calls, so sinking them here keeps them focused.
private final class NullAlertService: AlertServiceType, @unchecked Sendable {
    func handle(_: Error, for _: AlertHandlerRequest) { }
    func image(error _: ImageLoadingError, for _: URL) { }
}

/// A `LemmyServiceType` fake whose `fetchSiteInfo()` always throws an
/// `unknownServerError` carrying a configurable HTTP status (403 → permanent,
/// 503 → transient once `OutboxFailureClass.classify` sees it), and counts every
/// call. The counter is read by the tests to verify sweep gating / abandonment.
private actor GiveUpLemmyService: LemmyServiceType {
    private(set) var fetchSiteInfoCallCount = 0
    private let httpStatusCode: Int

    init(httpStatusCode: Int) {
        self.httpStatusCode = httpStatusCode
    }

    func fetchSiteInfo() async throws {
        fetchSiteInfoCallCount += 1
        throw LemmyApiError.unknownServerError(httpStatusCode: httpStatusCode, error: nil)
    }

    // MARK: - Unused protocol requirements (trap if reached)

    func getSiteInfo() async throws -> LemmyKit.SiteInfo {
        giveUpUnreachable()
    }

    func unreadCount() async throws -> UnreadCount {
        giveUpUnreachable()
    }

    func setShowNsfw(_: Bool) async throws {
        giveUpUnreachable()
    }

    func setBlurNsfw(_: Bool) async throws {
        giveUpUnreachable()
    }

    func setDefaultSortType(_: Lemmy.SortType) async throws {
        giveUpUnreachable()
    }

    func saveProfile(displayName _: String?, bio _: String?, avatar _: String?, banner _: String?, showScores _: Bool, showBotAccounts _: Bool, showReadPosts _: Bool, showAvatars _: Bool, defaultListingType _: Lemmy.ListingType) async throws {
        giveUpUnreachable()
    }

    func fetchPersonInfo(serverPersonId _: Lemmy.PersonID) async throws {
        giveUpUnreachable()
    }

    func fetchPersonContent(serverPersonId _: Lemmy.PersonID, sort _: Lemmy.SortType, page _: Int64) async throws -> PersonContentPage {
        giveUpUnreachable()
    }

    func fetchCommunityInfo(serverCommunityId _: Lemmy.CommunityID) async throws {
        giveUpUnreachable()
    }

    func fetchCommunityInfo(communityName _: String) async throws -> Lemmy.CommunityID {
        giveUpUnreachable()
    }

    func search(query _: String, type _: Lemmy.SearchType, sort _: Lemmy.SortType, listingType _: Lemmy.ListingType, page _: Int64) async throws -> LemmyKit.SearchResults {
        giveUpUnreachable()
    }

    func listCommunities(type _: Lemmy.ListingType, sort _: Lemmy.SortType?, limit _: Int64?) async throws -> [Lemmy.CommunityView] {
        giveUpUnreachable()
    }

    func setSubscribed(serverCommunityId _: Lemmy.CommunityID, subscribed _: Bool) async throws {
        giveUpUnreachable()
    }

    func vote(serverPostId _: Lemmy.PostID, vote _: VoteStatus.Action) async throws {
        giveUpUnreachable()
    }

    func vote(serverCommentId _: Lemmy.CommentID, vote _: VoteStatus.Action) async throws {
        giveUpUnreachable()
    }

    func createComment(serverPostId _: Lemmy.PostID, content _: String, parentCommentId _: Lemmy.CommentID?) async throws {
        giveUpUnreachable()
    }

    func createPost(serverCommunityId _: Lemmy.CommunityID, name _: String, url _: String?, body _: String?, nsfw _: Bool) async throws -> Lemmy.PostID {
        giveUpUnreachable()
    }

    func uploadImage(imageData _: Data, fileName _: String, mimeType _: String) async throws -> URL {
        giveUpUnreachable()
    }

    func setSaved(serverPostId _: Lemmy.PostID, saved _: Bool) async throws {
        giveUpUnreachable()
    }

    func setSaved(serverCommentId _: Lemmy.CommentID, saved _: Bool) async throws {
        giveUpUnreachable()
    }

    func deleteComment(serverCommentId _: Lemmy.CommentID, deleted _: Bool) async throws {
        giveUpUnreachable()
    }

    func deletePost(serverPostId _: Lemmy.PostID, deleted _: Bool) async throws {
        giveUpUnreachable()
    }

    func fetchPostInfo(serverPostId _: Lemmy.PostID) async throws {
        giveUpUnreachable()
    }

    func hidePost(serverPostId _: Lemmy.PostID, hidden _: Bool) async throws {
        giveUpUnreachable()
    }

    func outboxFailureEvents() async -> AsyncStream<OutboxFailure> {
        AsyncStream { $0.finish() }
    }

    func drainPendingOutbox() async {
        giveUpUnreachable()
    }

    func saveDraft(_: OutboundDraftInput) async throws -> String {
        giveUpUnreachable()
    }

    func submitDraft(clientToken _: String) async {
        giveUpUnreachable()
    }

    func retryComposition(clientToken _: String) async {
        giveUpUnreachable()
    }

    func discardComposition(clientToken _: String) async {
        giveUpUnreachable()
    }

    func loadDraft(draftKey _: String) async throws -> OutboundContentRecord? {
        giveUpUnreachable()
    }

    func saveDirectMessageDraft(body _: String, recipientServerPersonId _: Int64) async throws -> String {
        giveUpUnreachable()
    }

    func sendDirectMessage(body _: String, recipientServerPersonId _: Int64) async throws -> String {
        giveUpUnreachable()
    }

    func applyOptimisticPostEdit(serverPostId _: Lemmy.PostID, title _: String, body _: String?, url _: String?, nsfw _: Bool) async {
        giveUpUnreachable()
    }

    func composerFailureEvents() async -> AsyncStream<ComposerOutboxFailure> {
        AsyncStream { $0.finish() }
    }

    func composerSuccessEvents() async -> AsyncStream<ComposerOutboxSuccess> {
        AsyncStream { $0.finish() }
    }

    func markAsRead(serverPostId _: Lemmy.PostID) async throws {
        giveUpUnreachable()
    }

    func fetchReplies(unreadOnly _: Bool, page _: Int64) async throws -> [InboxCommentNotification] {
        giveUpUnreachable()
    }

    func fetchMentions(unreadOnly _: Bool, page _: Int64) async throws -> [InboxCommentNotification] {
        giveUpUnreachable()
    }

    func fetchPrivateMessages(unreadOnly _: Bool, page _: Int64) async throws -> [IncomingPrivateMessage] {
        giveUpUnreachable()
    }

    func markInboxItemAsRead(reference _: InboxItemReadReference, read _: Bool) async throws {
        giveUpUnreachable()
    }

    func markPrivateMessageAsRead(privateMessageId _: Lemmy.PrivateMessageID, read _: Bool) async throws {
        giveUpUnreachable()
    }

    func markAllInboxAsRead() async throws {
        giveUpUnreachable()
    }

    func sendPrivateMessage(content _: String, recipientId _: Lemmy.PersonID) async throws -> Lemmy.PrivateMessageView {
        giveUpUnreachable()
    }

    func setBlocked(serverPersonId _: Lemmy.PersonID, blocked _: Bool) async throws {
        giveUpUnreachable()
    }

    func setBlocked(serverCommunityId _: Lemmy.CommunityID, blocked _: Bool) async throws {
        giveUpUnreachable()
    }

    func reportPost(serverPostId _: Lemmy.PostID, reason _: String) async throws {
        giveUpUnreachable()
    }

    func reportComment(serverCommentId _: Lemmy.CommentID, reason _: String) async throws {
        giveUpUnreachable()
    }

    func fetchBlockedList() async throws -> BlockedList {
        giveUpUnreachable()
    }

    func fetchModerationCapability() async throws -> ModerationCapability {
        giveUpUnreachable()
    }

    func removePost(serverPostId _: Lemmy.PostID, removed _: Bool, reason _: String?) async throws {
        giveUpUnreachable()
    }

    func lockPost(serverPostId _: Lemmy.PostID, locked _: Bool) async throws {
        giveUpUnreachable()
    }

    func featurePost(serverPostId _: Lemmy.PostID, featured _: Bool, local _: Bool) async throws {
        giveUpUnreachable()
    }

    func removeComment(serverCommentId _: Lemmy.CommentID, removed _: Bool, reason _: String?) async throws {
        giveUpUnreachable()
    }

    func distinguishComment(serverCommentId _: Lemmy.CommentID, distinguished _: Bool) async throws {
        giveUpUnreachable()
    }

    func banFromCommunity(serverCommunityId _: Lemmy.CommunityID, serverPersonId _: Lemmy.PersonID, ban _: Bool, removeData _: Bool, reason _: String?) async throws {
        giveUpUnreachable()
    }

    func resolveObject(query _: String) async throws -> ResolvedLemmyObject {
        giveUpUnreachable()
    }

    func fetchFeed(_: FeedHandle, pageCursor _: String?, showNsfw _: Bool) async throws -> String? {
        giveUpUnreachable()
    }

    func fetchComments(serverPostId _: Lemmy.PostID, sortType _: Lemmy.CommentSortType) async throws {
        giveUpUnreachable()
    }
}

private func giveUpUnreachable(_ function: StaticString = #function) -> Never {
    fatalError("GiveUpLemmyService.\(function) must not be called in SchedulerServiceGiveUpTests")
}

/// Minimal `@MainActor` fake for `AccountServiceType` that returns a single shared
/// `LemmyServiceType` for every keychainId. All other protocol requirements trap.
@MainActor
private final class GiveUpAccountService: AccountServiceType {
    let stubbedLemmyService: any LemmyServiceType

    init(lemmyService: any LemmyServiceType) {
        stubbedLemmyService = lemmyService
    }

    func lemmyService(forAccountKeychainId _: String) -> any LemmyServiceType {
        stubbedLemmyService
    }

    func instanceActorId(forAccountKeychainId _: String) -> InstanceActorId? {
        InstanceActorId(from: "https://giveup-test.example.com")
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
        fatalError("not used in SchedulerServiceGiveUpTests")
    }
}

// MARK: - GiveUpClockBox

/// A reference-type clock wrapper so the `@Sendable` `now` closure can
/// capture a mutable date without triggering a Swift 6 data-race diagnostic.
/// Both the closure (called from `@MainActor` SchedulerService) and the
/// test mutations run on `@MainActor`, so concurrent access never occurs.
private final class GiveUpClockBox: @unchecked Sendable {
    var date: Date
    init(_ date: Date) {
        self.date = date
    }
}

// MARK: - SchedulerServiceGiveUpTests

/// Verifies that `SchedulerService`'s signed-out sweep records the *persisted*
/// give-up state (via `recordSiteInfoPermanentFailure` / `recordSiteInfoTransientFailure`)
/// and emits a `site.giveUp` diagnostic exactly once when an instance's site info
/// permanently fails `siteInfoGiveUpThreshold` times in a row — after which the
/// sweep query stops selecting it. Transient failures never abandon.
///
/// The suite is `@MainActor` (SchedulerService is `@MainActor`) and serialized
/// because the fake AccountService is also `@MainActor`.
@MainActor
@Suite(.serialized)
struct SchedulerServiceGiveUpTests {
    /// Seed one non-ephemeral signed-out account whose home site is awaiting its
    /// first site-info import (`name IS NULL`), so it is eligible for the sweep.
    /// Returns the site's row id so the test can read back the persisted state.
    private func seedSignedOutSite(_ appDatabase: AppDatabase, keychainId: String) async throws -> Int64 {
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://giveup-test.example.com", createdAt: Date(), updatedAt: Date())
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: true,
                isEphemeral: false
            )
            try account.insert(db)
            return site.id!
        }
    }

    private func makeService(
        appDatabase: AppDatabase,
        lemmyService: any LemmyServiceType,
        diagnostics: DiagnosticLogSpy,
        clock: GiveUpClockBox
    ) -> SchedulerService {
        SchedulerService(
            appDatabase: appDatabase,
            accountService: GiveUpAccountService(lemmyService: lemmyService),
            alertService: NullAlertService(),
            diagnostics: diagnostics,
            now: { clock.date },
            reachabilityMonitor: StaticReachabilityMonitor(isOnline: true)
        )
    }

    /// A signed-out account whose getSite throws a permanent 403 on every tick is
    /// abandoned after siteInfoGiveUpThreshold ticks: it stops being attempted and
    /// a site.giveUp diagnostic is recorded exactly once.
    @Test
    func permanentFailuresAbandonSiteAndRecordGiveUp() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let keychainId = "kc-giveup-permanent"
        let siteId = try await seedSignedOutSite(appDatabase, keychainId: keychainId)

        let fakeLemmy = GiveUpLemmyService(httpStatusCode: 403)
        let diagnostics = DiagnosticLogSpy()
        let clock = GiveUpClockBox(Date(timeIntervalSince1970: 2_000_000))
        let service = makeService(appDatabase: appDatabase, lemmyService: fakeLemmy, diagnostics: diagnostics, clock: clock)

        // Drive threshold + 2 ticks. Between each tick, step the clock 3 h forward —
        // well past every pre-abandonment back-off window (max ~40 min), so the
        // persisted `siteInfoNextAttemptAt` gate lets the sweep re-select the site
        // each time until it is abandoned at the threshold.
        let threeHours: TimeInterval = 3 * 60 * 60
        for _ in 0..<(AppDatabase.siteInfoGiveUpThreshold + 2) {
            await service.tick()
            clock.date = clock.date.addingTimeInterval(threeHours)
        }

        // site.giveUp is emitted exactly once, at the threshold.
        let giveUpEvents = diagnostics.events(matching: "site.giveUp")
        #expect(giveUpEvents.count == 1)
        let giveUp = try #require(giveUpEvents.first)
        #expect(giveUp.category == .site)
        #expect(giveUp.level == .notice)
        #expect(giveUp.instance == "giveup-test.example.com")
        #expect(giveUp.metadata?["failureCount"] == String(AppDatabase.siteInfoGiveUpThreshold))

        // After abandonment the sweep no longer selects the site, so exactly
        // `siteInfoGiveUpThreshold` fetches were attempted (the two extra ticks
        // are no-ops).
        let callCount = await fakeLemmy.fetchSiteInfoCallCount
        #expect(callCount == AppDatabase.siteInfoGiveUpThreshold)

        // The persisted counter reflects abandonment across relaunches.
        let site = try await appDatabase.writer.read { db in try SiteRecord.fetchOne(db, key: siteId) }
        #expect(site?.siteInfoConsecutivePermanentFailures == AppDatabase.siteInfoGiveUpThreshold)
    }

    /// Transient (503) failures never abandon: the account keeps being attempted
    /// and the persisted permanent counter stays at zero.
    @Test
    func transientFailuresNeverAbandon() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let keychainId = "kc-giveup-transient"
        let siteId = try await seedSignedOutSite(appDatabase, keychainId: keychainId)

        let fakeLemmy = GiveUpLemmyService(httpStatusCode: 503)
        let diagnostics = DiagnosticLogSpy()
        let clock = GiveUpClockBox(Date(timeIntervalSince1970: 2_000_000))
        let service = makeService(appDatabase: appDatabase, lemmyService: fakeLemmy, diagnostics: diagnostics, clock: clock)

        // Drive many ticks, stepping past the short transient retry window (5 min)
        // each time so the sweep re-selects the site on every tick.
        let sixMinutes: TimeInterval = 6 * 60
        let tickCount = AppDatabase.siteInfoGiveUpThreshold + 3
        for _ in 0..<tickCount {
            await service.tick()
            clock.date = clock.date.addingTimeInterval(sixMinutes)
        }

        // Never abandoned: no give-up event, attempted on every tick, and the
        // permanent counter never moved off zero.
        #expect(diagnostics.events(matching: "site.giveUp").isEmpty)
        let callCount = await fakeLemmy.fetchSiteInfoCallCount
        #expect(callCount == tickCount)
        let site = try await appDatabase.writer.read { db in try SiteRecord.fetchOne(db, key: siteId) }
        #expect(site?.siteInfoConsecutivePermanentFailures == 0)
    }
}
