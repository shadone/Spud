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
@testable import Spud
@testable import SpudDataKit

// MARK: - Test doubles

/// `LemmyServiceType` stub whose `fetchPrivateMessages` returns a queued sequence
/// of pages and records the cursors it was called with, so a test can drive and
/// assert `DMThreadViewModel`'s load-earlier paging. Every other requirement
/// traps — load-earlier only exercises `fetchPrivateMessages`. Mirrors the shape
/// of `RecordingSendLemmyService` in `DMThreadViewModelSendGuardTests.swift`.
private actor QueuedPMLemmyService: LemmyServiceType {
    /// One page the stub will hand back, in queue order.
    struct Page {
        let messages: [IncomingPrivateMessage]
        let nextCursor: String?
    }

    private var pages: [Page]
    /// The `pageCursor` argument of each `fetchPrivateMessages` call, in order.
    private(set) var requestedCursors: [String?] = []

    init(pages: [Page]) {
        self.pages = pages
    }

    var fetchCallCount: Int {
        requestedCursors.count
    }

    func fetchPrivateMessages(unreadOnly _: Bool, pageCursor: String?) async throws -> (messages: [IncomingPrivateMessage], nextCursor: String?) {
        requestedCursors.append(pageCursor)
        guard !pages.isEmpty else {
            return (messages: [], nextCursor: nil)
        }
        let page = pages.removeFirst()
        return (messages: page.messages, nextCursor: page.nextCursor)
    }

    // MARK: Unused protocol stubs

    func sendDirectMessage(body _: String, recipientServerPersonId _: Int64) async throws -> String {
        trap()
    }

    func fetchFeed(_: FeedHandle, pageCursor _: String?, showNsfw _: Bool) async throws -> String? {
        trap()
    }

    func fetchComments(serverPostId _: Lemmy.PostID, sortType _: Lemmy.CommentSortType) async throws {
        trap()
    }

    func fetchSiteInfo() async throws {
        trap()
    }

    func getSiteInfo() async throws -> LemmyKit.SiteInfo {
        trap()
    }

    func setShowNsfw(_: Bool) async throws {
        trap()
    }

    func setBlurNsfw(_: Bool) async throws {
        trap()
    }

    func setDefaultSortType(_: Lemmy.SortType) async throws {
        trap()
    }

    func saveProfile(
        displayName _: String?,
        bio _: String?,
        avatar _: ProfileImageEdit,
        banner _: ProfileImageEdit,
        showScores _: Bool,
        showBotAccounts _: Bool,
        showReadPosts _: Bool,
        showAvatars _: Bool,
        defaultListingType _: Lemmy.ListingType
    ) async throws {
        trap()
    }

    func fetchPersonInfo(serverPersonId _: Lemmy.PersonID) async throws {
        trap()
    }

    func fetchPersonContent(serverPersonId _: Lemmy.PersonID, sort _: Lemmy.SortType, page _: Int64) async throws -> PersonContentPage {
        trap()
    }

    func fetchCommunityInfo(serverCommunityId _: Lemmy.CommunityID) async throws {
        trap()
    }

    func fetchCommunityInfo(communityName _: String) async throws -> Lemmy.CommunityID {
        trap()
    }

    func search(query _: String, type _: Lemmy.SearchType, sort _: Lemmy.SortType?, listingType _: Lemmy.ListingType, page _: Int64) async throws -> LemmyKit.SearchResults {
        trap()
    }

    func listCommunities(type _: Lemmy.ListingType, sort _: Lemmy.SortType?, limit _: Int64?) async throws -> [Lemmy.CommunityView] {
        trap()
    }

    func setSubscribed(serverCommunityId _: Lemmy.CommunityID, subscribed _: Bool) async throws {
        trap()
    }

    func vote(serverPostId _: Lemmy.PostID, vote _: VoteStatus.Action) async throws {
        trap()
    }

    func vote(serverCommentId _: Lemmy.CommentID, vote _: VoteStatus.Action) async throws {
        trap()
    }

    func createComment(serverPostId _: Lemmy.PostID, content _: String, parentCommentId _: Lemmy.CommentID?) async throws {
        trap()
    }

    func createPost(serverCommunityId _: Lemmy.CommunityID, name _: String, url _: String?, body _: String?, nsfw _: Bool) async throws -> Lemmy.PostID {
        trap()
    }

    func uploadImage(imageData _: Data, fileName _: String, mimeType _: String) async throws -> URL {
        trap()
    }

    func setSaved(serverPostId _: Lemmy.PostID, saved _: Bool) async throws {
        trap()
    }

    func setSaved(serverCommentId _: Lemmy.CommentID, saved _: Bool) async throws {
        trap()
    }

    func deleteComment(serverCommentId _: Lemmy.CommentID, deleted _: Bool) async throws {
        trap()
    }

    func deletePost(serverPostId _: Lemmy.PostID, deleted _: Bool) async throws {
        trap()
    }

    func fetchPostInfo(serverPostId _: Lemmy.PostID) async throws {
        trap()
    }

    func hidePost(serverPostId _: Lemmy.PostID, hidden _: Bool) async throws {
        trap()
    }

    func outboxFailureEvents() async -> AsyncStream<OutboxFailure> {
        AsyncStream { $0.finish() }
    }

    func drainPendingOutbox() async {
        trap()
    }

    func saveDraft(_: OutboundDraftInput) async throws -> String {
        trap()
    }

    func submitDraft(clientToken _: String) async {
        trap()
    }

    func retryComposition(clientToken _: String) async {
        trap()
    }

    func discardComposition(clientToken _: String) async {
        trap()
    }

    func loadDraft(draftKey _: String) async throws -> OutboundContentRecord? {
        trap()
    }

    func saveDirectMessageDraft(body _: String, recipientServerPersonId _: Int64) async throws -> String {
        trap()
    }

    func applyOptimisticPostEdit(serverPostId _: Lemmy.PostID, title _: String, body _: String?, url _: String?, nsfw _: Bool) async {
        trap()
    }

    func composerFailureEvents() async -> AsyncStream<ComposerOutboxFailure> {
        AsyncStream { $0.finish() }
    }

    func composerSuccessEvents() async -> AsyncStream<ComposerOutboxSuccess> {
        AsyncStream { $0.finish() }
    }

    func markAsRead(serverPostId _: Lemmy.PostID) async throws {
        trap()
    }

    func fetchReplies(unreadOnly _: Bool, page _: Int64) async throws -> [InboxCommentNotification] {
        trap()
    }

    func fetchMentions(unreadOnly _: Bool, page _: Int64) async throws -> [InboxCommentNotification] {
        trap()
    }

    func unreadCount() async throws -> UnreadCount {
        trap()
    }

    func markInboxItemAsRead(reference _: InboxItemReadReference, read _: Bool) async throws {
        trap()
    }

    func markPrivateMessageAsRead(privateMessageId _: Lemmy.PrivateMessageID, read _: Bool) async throws {
        trap()
    }

    func markAllInboxAsRead() async throws {
        trap()
    }

    func sendPrivateMessage(content _: String, recipientId _: Lemmy.PersonID) async throws -> Lemmy.PrivateMessageView {
        trap()
    }

    func setBlocked(serverPersonId _: Lemmy.PersonID, blocked _: Bool) async throws {
        trap()
    }

    func setBlocked(serverCommunityId _: Lemmy.CommunityID, blocked _: Bool) async throws {
        trap()
    }

    func reportPost(serverPostId _: Lemmy.PostID, reason _: String) async throws {
        trap()
    }

    func reportComment(serverCommentId _: Lemmy.CommentID, reason _: String) async throws {
        trap()
    }

    func fetchBlockedList() async throws -> BlockedList {
        trap()
    }

    func fetchModerationCapability() async throws -> ModerationCapability {
        trap()
    }

    func removePost(serverPostId _: Lemmy.PostID, removed _: Bool, reason _: String?) async throws {
        trap()
    }

    func lockPost(serverPostId _: Lemmy.PostID, locked _: Bool) async throws {
        trap()
    }

    func featurePost(serverPostId _: Lemmy.PostID, featured _: Bool, local _: Bool) async throws {
        trap()
    }

    func removeComment(serverCommentId _: Lemmy.CommentID, removed _: Bool, reason _: String?) async throws {
        trap()
    }

    func distinguishComment(serverCommentId _: Lemmy.CommentID, distinguished _: Bool) async throws {
        trap()
    }

    func banFromCommunity(serverCommunityId _: Lemmy.CommunityID, serverPersonId _: Lemmy.PersonID, ban _: Bool, removeData _: Bool, reason _: String?) async throws {
        trap()
    }

    func resolveObject(query _: String) async throws -> ResolvedLemmyObject {
        trap()
    }
}

/// `AccountServiceType` stub returning the queued Lemmy double and an
/// all-available capability set (load-earlier never gates). Mirrors
/// `FakeSendGuardAccountService`.
@MainActor
private final class FakeLoadOlderAccountService: AccountServiceType {
    let lemmyServiceDouble: QueuedPMLemmyService

    init(lemmyServiceDouble: QueuedPMLemmyService) {
        self.lemmyServiceDouble = lemmyServiceDouble
    }

    func lemmyService(forAccountKeychainId _: String) -> LemmyServiceType {
        lemmyServiceDouble
    }

    func instanceCapabilities(forAccountKeychainId _: String) -> InstanceCapabilities {
        .allAvailable
    }

    // MARK: Unused stubs

    func accountForSignedOut(forInstance _: InstanceActorId, isServiceAccount _: Bool) -> String {
        ""
    }

    func signInAsSignedOut(atInstance _: InstanceActorId) { }
    #if DEBUG
    func seedSignedInDefaultAccount(atInstance _: InstanceActorId) { }
    #endif
    func login(atInstance _: InstanceActorId, username _: String, password _: String, totp2faToken _: String?) async throws { }
    func register(atInstance _: InstanceActorId, username _: String, email _: String?, password _: String, passwordVerify _: String, showNsfw _: Bool, captchaUuid _: String?, captchaAnswer _: String?, answer _: String?) async throws -> AccountServiceRegisterResult {
        fatalError()
    }

    func passwordReset(atInstance _: InstanceActorId, email _: String) async throws { }
    func logout(forAccountKeychainId _: String) { }
    func removeAccount(forAccountKeychainId _: String) { }
    func currentDefaultAccountKeychainId() -> String? {
        nil
    }

    func isSignedOut(forAccountKeychainId _: String) -> Bool {
        false
    }

    func setDefaultAccount(forAccountKeychainId _: String) { }
    func accountKeychainId(forInstance _: InstanceActorId) -> String {
        ""
    }

    func instanceActorId(forAccountKeychainId _: String) -> InstanceActorId? {
        nil
    }

    func defaultListingType(forAccountKeychainId _: String) -> Lemmy.ListingType {
        .All
    }

    func defaultSortType(forAccountKeychainId _: String) -> Lemmy.SortType {
        .Hot
    }

    func setDefaultSortType(_: Lemmy.SortType, forAccountKeychainId _: String) { }

    func refreshSiteInfoOnDemandIfNeeded(forAccountKeychainId _: String) { }

    func createFeed(type _: FeedType, forAccountKeychainId _: String) async throws -> FeedHandle {
        fatalError()
    }

    func defaultFeedHandle(forAccountKeychainId _: String) -> FeedHandle? {
        nil
    }
}

/// No-op alert double — load-earlier surfaces no alerts on the happy path.
private final class NoOpAlertService: AlertServiceType, @unchecked Sendable {
    func handle(_: Error, for _: AlertHandlerRequest) { }
    func image(error _: ImageLoadingError, for _: URL) { }
}

/// No-op unread-count double.
@MainActor
private final class NoOpUnreadCountService: UnreadCountServiceType {
    var unreadCount: UnreadCount = .zero
    func refresh(accountKeychainId _: String) async { }
    func decrement(replies _: Int, mentions _: Int, privateMessages _: Int) { }
    func reset() { }
}

// MARK: - Tests

/// Covers `DMThreadViewModel.loadOlder`: the load-earlier paging that closes DM
/// history navigation. Because Lemmy has no per-conversation history endpoint,
/// `loadOlder` walks the account's OVERALL private-message list (bounded per
/// invocation) until it persists older messages for THIS thread, exhausts the
/// list, or hits the page cap — and the store is upsert-only, so re-walking is
/// idempotent. These are DB-backed: a real in-memory `AppDatabase` verifies the
/// upsert, and the stub's recorded cursors verify the cursor advances.
@MainActor
struct DMThreadViewModelLoadOlderTests {
    private let keychainId = "kc-dm-load-older-test"

    private enum PID {
        static let me: Int64 = 100
        static let alice: Int64 = 200
        static let bob: Int64 = 300
    }

    // MARK: Fixtures

    private static func person(id: Int64, name: String) -> Lemmy.Person {
        Lemmy.Person(
            id: id,
            name: name,
            displayName: name.capitalized,
            avatarUrl: nil,
            bannerUrl: nil,
            bio: nil,
            apId: "https://\(name).test/u/\(name)",
            matrixUserId: nil,
            botAccount: false,
            deleted: false,
            local: true,
            publishedAt: Date(timeIntervalSince1970: 1_683_349_689),
            updatedAt: nil,
            postCount: 0,
            commentCount: 0
        )
    }

    /// Build an `IncomingPrivateMessage` between `creatorId` and `recipientId`.
    private static func message(
        messageId: Int64,
        creatorId: Int64,
        recipientId: Int64,
        content: String = "msg",
        published: Date = Date(timeIntervalSince1970: 1000)
    ) -> IncomingPrivateMessage {
        let creator = person(id: creatorId, name: "p\(creatorId)")
        let recipient = person(id: recipientId, name: "p\(recipientId)")
        let pm = LemmyKit.PrivateMessage(
            id: messageId,
            creatorId: creatorId,
            recipientId: recipientId,
            content: content,
            deleted: false,
            deletedByRecipient: false,
            removed: false,
            local: true,
            apId: "https://x.test/private_message/\(messageId)",
            publishedAt: published,
            updatedAt: nil
        )
        let view = Lemmy.PrivateMessageView(privateMessage: pm, creator: creator, recipient: recipient)
        return IncomingPrivateMessage(view: view, isRead: true)
    }

    /// A message from Alice (this thread's correspondent) to me.
    private static func aliceMessage(id: Int64) -> IncomingPrivateMessage {
        message(messageId: id, creatorId: PID.alice, recipientId: PID.me)
    }

    /// A message that belongs to a DIFFERENT correspondent (Bob), so it does NOT
    /// count toward this thread when `loadOlder` decides whether a page yielded.
    private static func bobMessage(id: Int64) -> IncomingPrivateMessage {
        message(messageId: id, creatorId: PID.bob, recipientId: PID.me)
    }

    private struct Fixture {
        let viewModel: DMThreadViewModel
        let lemmyServiceDouble: QueuedPMLemmyService
        let appDatabase: AppDatabase
        let accountId: Int64
    }

    private func makeFixture(pages: [QueuedPMLemmyService.Page]) async throws -> Fixture {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try await appDatabase.writer.write { db -> Int64 in
            var instance = InstanceRecord(actorId: "https://dm.test")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return account.id!
        }

        let lemmyServiceDouble = QueuedPMLemmyService(pages: pages)
        let accountService = FakeLoadOlderAccountService(lemmyServiceDouble: lemmyServiceDouble)
        let scope = AccountScope(accountKeychainId: keychainId, accountService: accountService)
        let viewModel = DMThreadViewModel(
            accountScope: scope,
            appDatabase: appDatabase,
            correspondentId: Lemmy.PersonID(PID.alice),
            correspondentName: "Alice",
            myPersonId: Lemmy.PersonID(PID.me),
            alertService: NoOpAlertService(),
            unreadCountService: NoOpUnreadCountService()
        )
        return Fixture(
            viewModel: viewModel,
            lemmyServiceDouble: lemmyServiceDouble,
            appDatabase: appDatabase,
            accountId: accountId
        )
    }

    /// Drive the initial `refresh()` (which seeds `nextPMCursor` from page 1) and
    /// wait, with a bounded poll, until page 1 is persisted — at which point the
    /// cursor is live and `loadOlder` can run. `refresh` sets the cursor before
    /// the upsert, so seeing the persisted message guarantees the cursor is set.
    private func seedFirstPage(_ fixture: Fixture, expectingMessageId messageId: Int64) async {
        fixture.viewModel.refresh(markRead: false)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let persisted = fixture.appDatabase.privateMessagesSync(accountId: fixture.accountId)
            if persisted.contains(where: { $0.serverMessageId == messageId }) {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - Cursor advance + persistence + reachedHistoryStart

    @Test
    func loadOlder_persistsOlderPage_advancesCursor_andReachesStartWhenExhausted() async throws {
        // Page 1 (from refresh): Alice #10, more history after (cursor "c1").
        // Load-older page (from "c1"): Alice #5, then the list is exhausted (nil).
        let fixture = try await makeFixture(pages: [
            .init(messages: [Self.aliceMessage(id: 10)], nextCursor: "c1"),
            .init(messages: [Self.aliceMessage(id: 5)], nextCursor: nil),
        ])

        await seedFirstPage(fixture, expectingMessageId: 10)
        #expect(fixture.viewModel.reachedHistoryStart == false)

        await fixture.viewModel.loadOlder()

        // The short page exhausted the list.
        #expect(fixture.viewModel.reachedHistoryStart == true)
        // refresh fetched with nil; loadOlder advanced to the stored "c1".
        let cursors = await fixture.lemmyServiceDouble.requestedCursors
        #expect(cursors == [nil, "c1"])
        // Both pages were upserted (upsert-only, oldest included).
        let ids = fixture.appDatabase.privateMessagesSync(accountId: fixture.accountId)
            .map(\.serverMessageId)
            .sorted()
        #expect(ids == [5, 10])
    }

    // MARK: - Bounded page-forward past pages with nothing for this thread

    @Test
    func loadOlder_walksPastPagesWithNoMessagesForThisThread_untilOneIsFound() async throws {
        // Page 1 (refresh): Alice #10, cursor "c1".
        // "c1": Bob only (nothing for Alice) → keep paging.
        // "c2": Bob only → keep paging.
        // "c3": Alice #7 → stop here.
        let fixture = try await makeFixture(pages: [
            .init(messages: [Self.aliceMessage(id: 10)], nextCursor: "c1"),
            .init(messages: [Self.bobMessage(id: 9)], nextCursor: "c2"),
            .init(messages: [Self.bobMessage(id: 8)], nextCursor: "c3"),
            .init(messages: [Self.aliceMessage(id: 7)], nextCursor: "c4"),
        ])

        await seedFirstPage(fixture, expectingMessageId: 10)

        await fixture.viewModel.loadOlder()

        // loadOlder walked "c1", "c2", "c3" (3 pages) then stopped on finding Alice.
        let cursors = await fixture.lemmyServiceDouble.requestedCursors
        #expect(cursors == [nil, "c1", "c2", "c3"])
        // Its cursor is not exhausted (the Alice page carried "c4").
        #expect(fixture.viewModel.reachedHistoryStart == false)
        // Every walked page was persisted (upsert-only), including the skipped-past
        // Bob messages and the found Alice message.
        let ids = fixture.appDatabase.privateMessagesSync(accountId: fixture.accountId)
            .map(\.serverMessageId)
            .sorted()
        #expect(ids == [7, 8, 9, 10])
    }

    // MARK: - Per-invocation cap

    @Test
    func loadOlder_stopsAtPageCap_whenNoMessagesForThisThreadFound() async throws {
        // Page 1 (refresh): Alice #10, cursor "c1". Then five Bob-only pages, each
        // with a non-nil cursor, so the list is never exhausted — the cap (5) must
        // stop the walk, leaving reachedHistoryStart false and the affordance live.
        var pages: [QueuedPMLemmyService.Page] = [
            .init(messages: [Self.aliceMessage(id: 100)], nextCursor: "c1"),
        ]
        for i in 1...5 {
            pages.append(.init(messages: [Self.bobMessage(id: Int64(50 - i))], nextCursor: "c\(i + 1)"))
        }
        let fixture = try await makeFixture(pages: pages)

        await seedFirstPage(fixture, expectingMessageId: 100)

        await fixture.viewModel.loadOlder()

        // Exactly the cap (5) load-older fetches, plus the initial refresh fetch.
        let cursors = await fixture.lemmyServiceDouble.requestedCursors
        #expect(cursors == [nil, "c1", "c2", "c3", "c4", "c5"])
        // Cap hit, but the list isn't exhausted — the user can continue.
        #expect(fixture.viewModel.reachedHistoryStart == false)

        // The cap is PER-INVOCATION: a second loadOlder continues from where the
        // first stopped (cursor "c6").
        await fixture.viewModel.loadOlder()
        let cursorsAfter = await fixture.lemmyServiceDouble.requestedCursors
        #expect(cursorsAfter.dropFirst(6).first == .some("c6"))
    }

    // MARK: - No-op once history start is reached

    @Test
    func loadOlder_isNoOp_afterReachedHistoryStart() async throws {
        // Page 1 (refresh) already exhausts the list (nil cursor).
        let fixture = try await makeFixture(pages: [
            .init(messages: [Self.aliceMessage(id: 10)], nextCursor: nil),
        ])

        await seedFirstPage(fixture, expectingMessageId: 10)
        #expect(fixture.viewModel.reachedHistoryStart == true)

        let before = await fixture.lemmyServiceDouble.fetchCallCount
        await fixture.viewModel.loadOlder()
        let after = await fixture.lemmyServiceDouble.fetchCallCount
        // Guarded out before any fetch.
        #expect(after == before)
    }
}

// MARK: - Trap helper

private func trap(_ function: StaticString = #function) -> Never {
    fatalError("Unexpected call to \(function) in DMThreadViewModelLoadOlderTests")
}
