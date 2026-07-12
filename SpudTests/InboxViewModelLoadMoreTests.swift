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
/// assert `InboxViewModel`'s conversation-list `loadMore` paging. Every other
/// requirement traps — conversation-list paging only exercises
/// `fetchPrivateMessages`. Mirrors `QueuedPMLemmyService` in
/// `DMThreadViewModelLoadOlderTests.swift`.
private actor QueuedInboxLemmyService: LemmyServiceType {
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

    func search(query _: String, type _: Lemmy.SearchType, sort _: Lemmy.SortType, listingType _: Lemmy.ListingType, page _: Int64) async throws -> LemmyKit.SearchResults {
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
/// all-available capability set. Mirrors `FakeLoadOlderAccountService`.
@MainActor
private final class FakeInboxLoadMoreAccountService: AccountServiceType {
    let lemmyServiceDouble: QueuedInboxLemmyService

    init(lemmyServiceDouble: QueuedInboxLemmyService) {
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

/// No-op alert double — happy-path paging surfaces no alerts.
private final class NoOpLoadMoreAlertService: AlertServiceType, @unchecked Sendable {
    func handle(_: Error, for _: AlertHandlerRequest) { }
    func image(error _: ImageLoadingError, for _: URL) { }
}

/// No-op unread-count double.
@MainActor
private final class NoOpLoadMoreUnreadCountService: UnreadCountServiceType {
    var unreadCount: UnreadCount = .zero
    func refresh(accountKeychainId _: String) async { }
    func decrement(replies _: Int, mentions _: Int, privateMessages _: Int) { }
    func reset() { }
}

// MARK: - Tests

/// Covers `InboxViewModel.loadMore`: the infinite-scroll paging that completes DM
/// pagination for the conversation LIST. The list pages the account's OVERALL
/// private-message list (the same list the DM thread's `loadOlder` walks) — but,
/// unlike a single thread, ANY persisted page advances it, so no bounded
/// per-correspondent walk is needed: one fetch + upsert per call. These are
/// DB-backed: a real in-memory `AppDatabase` verifies the upsert, and the stub's
/// recorded cursors verify the cursor advances.
@MainActor
struct InboxViewModelLoadMoreTests {
    private let keychainId = "kc-inbox-load-more-test"

    private enum PID {
        static let me: Int64 = 100
        static let alice: Int64 = 200
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

    /// A private message from Alice to me. The conversation list stores every
    /// correspondent's messages, so any page advances it (no per-thread filter).
    private static func message(id: Int64) -> IncomingPrivateMessage {
        let creator = person(id: PID.alice, name: "p\(PID.alice)")
        let recipient = person(id: PID.me, name: "p\(PID.me)")
        let pm = LemmyKit.PrivateMessage(
            id: id,
            creatorId: PID.alice,
            recipientId: PID.me,
            content: "msg \(id)",
            deleted: false,
            deletedByRecipient: false,
            removed: false,
            local: true,
            apId: "https://x.test/private_message/\(id)",
            publishedAt: Date(timeIntervalSince1970: 1000 + Double(id)),
            updatedAt: nil
        )
        let view = Lemmy.PrivateMessageView(privateMessage: pm, creator: creator, recipient: recipient)
        return IncomingPrivateMessage(view: view, isRead: true)
    }

    private struct Fixture {
        let viewModel: InboxViewModel
        let lemmyServiceDouble: QueuedInboxLemmyService
        let appDatabase: AppDatabase
        let accountId: Int64
    }

    private func makeFixture(pages: [QueuedInboxLemmyService.Page]) async throws -> Fixture {
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

        let lemmyServiceDouble = QueuedInboxLemmyService(pages: pages)
        let accountService = FakeInboxLoadMoreAccountService(lemmyServiceDouble: lemmyServiceDouble)
        let scope = AccountScope(accountKeychainId: keychainId, accountService: accountService)
        let viewModel = InboxViewModel(
            accountScope: scope,
            appDatabase: appDatabase,
            isSignedIn: true,
            myPersonId: Lemmy.PersonID(PID.me),
            alertService: NoOpLoadMoreAlertService(),
            unreadCountService: NoOpLoadMoreUnreadCountService()
        )
        return Fixture(
            viewModel: viewModel,
            lemmyServiceDouble: lemmyServiceDouble,
            appDatabase: appDatabase,
            accountId: accountId
        )
    }

    /// Drive the initial `loadMessages()` (which seeds `nextPMCursor` / `reachedEnd`
    /// from page 1) and wait, with a bounded poll, until page 1 is persisted — at
    /// which point the cursor is live and `loadMore` can run. `refreshMessages`
    /// sets the cursor before the upsert, so seeing the persisted message
    /// guarantees the cursor is set.
    private func seedFirstPage(_ fixture: Fixture, expectingMessageId messageId: Int64) async {
        fixture.viewModel.loadMessages()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let persisted = fixture.appDatabase.privateMessagesSync(accountId: fixture.accountId)
            if persisted.contains(where: { $0.serverMessageId == messageId }) {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - Happy path: persist + advance cursor + reach end

    @Test
    func loadMore_persistsNextPage_advancesCursor_andReachesEndWhenExhausted() async throws {
        // Page 1 (from refresh): message #10, more after (cursor "c1").
        // Load-more page (from "c1"): message #5, then the list is exhausted (nil).
        let fixture = try await makeFixture(pages: [
            .init(messages: [Self.message(id: 10)], nextCursor: "c1"),
            .init(messages: [Self.message(id: 5)], nextCursor: nil),
        ])

        await seedFirstPage(fixture, expectingMessageId: 10)
        // Page 1 carried a cursor, so there is more to load.
        #expect(fixture.viewModel.reachedEnd == false)

        await fixture.viewModel.loadMore()

        // The short page exhausted the list.
        #expect(fixture.viewModel.reachedEnd == true)
        // refresh fetched with nil; loadMore advanced to the stored "c1".
        let cursors = await fixture.lemmyServiceDouble.requestedCursors
        #expect(cursors == [nil, "c1"])
        // Both pages were upserted (upsert-only, nothing deleted).
        let ids = fixture.appDatabase.privateMessagesSync(accountId: fixture.accountId)
            .map(\.serverMessageId)
            .sorted()
        #expect(ids == [5, 10])
    }

    // MARK: - No-op before the first page has loaded (cursor unseeded)

    @Test
    func loadMore_isNoOp_beforeFirstPageLoaded() async throws {
        let fixture = try await makeFixture(pages: [
            .init(messages: [Self.message(id: 10)], nextCursor: "c1"),
        ])

        // No `loadMessages`/refresh yet → `nextPMCursor` is nil, so loadMore must
        // guard out before touching the service.
        let before = await fixture.lemmyServiceDouble.fetchCallCount
        await fixture.viewModel.loadMore()
        let after = await fixture.lemmyServiceDouble.fetchCallCount
        #expect(before == 0)
        #expect(after == 0)
        #expect(fixture.viewModel.isLoadingMore == false)
    }

    // MARK: - No-op once the end is reached

    @Test
    func loadMore_isNoOp_afterReachedEnd() async throws {
        // Page 1 (refresh) already exhausts the list (nil cursor).
        let fixture = try await makeFixture(pages: [
            .init(messages: [Self.message(id: 10)], nextCursor: nil),
        ])

        await seedFirstPage(fixture, expectingMessageId: 10)
        #expect(fixture.viewModel.reachedEnd == true)

        let before = await fixture.lemmyServiceDouble.fetchCallCount
        await fixture.viewModel.loadMore()
        let after = await fixture.lemmyServiceDouble.fetchCallCount
        // Guarded out before any fetch.
        #expect(after == before)
    }

    // MARK: - Re-entrancy guard: concurrent calls fetch only once

    @Test
    func loadMore_doesNotDoubleFetch_whileAlreadyLoading() async throws {
        let fixture = try await makeFixture(pages: [
            .init(messages: [Self.message(id: 10)], nextCursor: "c1"),
            .init(messages: [Self.message(id: 5)], nextCursor: "c2"),
        ])

        await seedFirstPage(fixture, expectingMessageId: 10)
        let before = await fixture.lemmyServiceDouble.fetchCallCount

        // Two concurrent loadMore calls: whichever runs first sets `isLoadingMore`
        // synchronously (on the main actor, before its first await) and the other
        // sees the guard and returns without fetching — so exactly one additional
        // fetch results.
        async let first: Void = fixture.viewModel.loadMore()
        async let second: Void = fixture.viewModel.loadMore()
        _ = await (first, second)

        let after = await fixture.lemmyServiceDouble.fetchCallCount
        #expect(after == before + 1)
    }
}

// MARK: - Trap helper

private func trap(_ function: StaticString = #function) -> Never {
    fatalError("Unexpected call to \(function) in InboxViewModelLoadMoreTests")
}
