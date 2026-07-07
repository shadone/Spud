//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUtilKit
import Testing
@testable import Spud

// MARK: - Test doubles

/// Records calls to `sendDirectMessage`. All other `LemmyServiceType`
/// requirements trap - the send-guard test only exercises `send(_:)`, and no
/// other call should ever be reached. Mirrors the shape of
/// `RecordingInboxLemmyService` in `InboxViewModelGatingTests.swift`.
private actor RecordingSendLemmyService: LemmyServiceType {
    private(set) var sendDirectMessageCallCount = 0

    func sendDirectMessage(body _: String, recipientServerPersonId _: Int64) async throws -> String {
        sendDirectMessageCallCount += 1
        return "client-token"
    }

    // MARK: Unused protocol stubs

    func fetchFeed(_: FeedHandle, pageCursor _: String?, showNsfw _: Bool) async throws -> String? {
        trap()
    }

    func fetchComments(serverPostId _: Components.Schemas.PostID, sortType _: Components.Schemas.CommentSortType) async throws {
        trap()
    }

    func fetchSiteInfo() async throws {
        trap()
    }

    func getSiteInfo() async throws -> Components.Schemas.GetSiteResponse {
        trap()
    }

    func setShowNsfw(_: Bool) async throws {
        trap()
    }

    func setBlurNsfw(_: Bool) async throws {
        trap()
    }

    func setDefaultSortType(_: Components.Schemas.SortType) async throws {
        trap()
    }

    func saveProfile(
        displayName _: String?,
        bio _: String?,
        avatar _: String?,
        banner _: String?,
        showScores _: Bool,
        showBotAccounts _: Bool,
        showReadPosts _: Bool,
        showAvatars _: Bool,
        defaultListingType _: Components.Schemas.ListingType
    ) async throws {
        trap()
    }

    func fetchPersonInfo(serverPersonId _: Components.Schemas.PersonID) async throws {
        trap()
    }

    func fetchPersonContent(serverPersonId _: Components.Schemas.PersonID, sort _: Components.Schemas.SortType, page _: Int64) async throws -> Components.Schemas.GetPersonDetailsResponse {
        trap()
    }

    func fetchCommunityInfo(serverCommunityId _: Components.Schemas.CommunityID) async throws {
        trap()
    }

    func fetchCommunityInfo(communityName _: String) async throws -> Components.Schemas.CommunityID {
        trap()
    }

    func search(query _: String, type _: Components.Schemas.SearchType, sort _: Components.Schemas.SortType, listingType _: Components.Schemas.ListingType, page _: Int64) async throws -> Components.Schemas.SearchResponse {
        trap()
    }

    func listCommunities(type _: Components.Schemas.ListingType, sort _: Components.Schemas.SortType?, limit _: Int64?) async throws -> [Components.Schemas.CommunityView] {
        trap()
    }

    func setSubscribed(serverCommunityId _: Components.Schemas.CommunityID, subscribed _: Bool) async throws {
        trap()
    }

    func vote(serverPostId _: Components.Schemas.PostID, vote _: VoteStatus.Action) async throws {
        trap()
    }

    func vote(serverCommentId _: Components.Schemas.CommentID, vote _: VoteStatus.Action) async throws {
        trap()
    }

    func createComment(serverPostId _: Components.Schemas.PostID, content _: String, parentCommentId _: Components.Schemas.CommentID?) async throws {
        trap()
    }

    func createPost(serverCommunityId _: Components.Schemas.CommunityID, name _: String, url _: String?, body _: String?, nsfw _: Bool) async throws -> Components.Schemas.PostID {
        trap()
    }

    func uploadImage(imageData _: Data, fileName _: String, mimeType _: String) async throws -> URL {
        trap()
    }

    func setSaved(serverPostId _: Components.Schemas.PostID, saved _: Bool) async throws {
        trap()
    }

    func setSaved(serverCommentId _: Components.Schemas.CommentID, saved _: Bool) async throws {
        trap()
    }

    func deleteComment(serverCommentId _: Components.Schemas.CommentID, deleted _: Bool) async throws {
        trap()
    }

    func deletePost(serverPostId _: Components.Schemas.PostID, deleted _: Bool) async throws {
        trap()
    }

    func fetchPostInfo(serverPostId _: Components.Schemas.PostID) async throws {
        trap()
    }

    func hidePost(serverPostId _: Components.Schemas.PostID, hidden _: Bool) async throws {
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

    func applyOptimisticPostEdit(serverPostId _: Components.Schemas.PostID, title _: String, body _: String?, url _: String?, nsfw _: Bool) async {
        trap()
    }

    func composerFailureEvents() async -> AsyncStream<ComposerOutboxFailure> {
        AsyncStream { $0.finish() }
    }

    func composerSuccessEvents() async -> AsyncStream<ComposerOutboxSuccess> {
        AsyncStream { $0.finish() }
    }

    func markAsRead(serverPostId _: Components.Schemas.PostID) async throws {
        trap()
    }

    func fetchReplies(unreadOnly _: Bool, page _: Int64) async throws -> Components.Schemas.GetRepliesResponse {
        trap()
    }

    func fetchMentions(unreadOnly _: Bool, page _: Int64) async throws -> Components.Schemas.GetPersonMentionsResponse {
        trap()
    }

    func fetchPrivateMessages(unreadOnly _: Bool, page _: Int64) async throws -> Components.Schemas.PrivateMessagesResponse {
        trap()
    }

    func unreadCount() async throws -> UnreadCount {
        trap()
    }

    func markReplyAsRead(commentReplyId _: Components.Schemas.CommentReplyID, read _: Bool) async throws {
        trap()
    }

    func markMentionAsRead(personMentionId _: Components.Schemas.PersonMentionID, read _: Bool) async throws {
        trap()
    }

    func markPrivateMessageAsRead(privateMessageId _: Components.Schemas.PrivateMessageID, read _: Bool) async throws {
        trap()
    }

    func markAllInboxAsRead() async throws {
        trap()
    }

    func sendPrivateMessage(content _: String, recipientId _: Components.Schemas.PersonID) async throws -> Components.Schemas.PrivateMessageView {
        trap()
    }

    func setBlocked(serverPersonId _: Components.Schemas.PersonID, blocked _: Bool) async throws {
        trap()
    }

    func setBlocked(serverCommunityId _: Components.Schemas.CommunityID, blocked _: Bool) async throws {
        trap()
    }

    func reportPost(serverPostId _: Components.Schemas.PostID, reason _: String) async throws {
        trap()
    }

    func reportComment(serverCommentId _: Components.Schemas.CommentID, reason _: String) async throws {
        trap()
    }

    func fetchBlockedList() async throws -> BlockedList {
        trap()
    }

    func fetchModerationCapability() async throws -> ModerationCapability {
        trap()
    }

    func removePost(serverPostId _: Components.Schemas.PostID, removed _: Bool, reason _: String?) async throws {
        trap()
    }

    func lockPost(serverPostId _: Components.Schemas.PostID, locked _: Bool) async throws {
        trap()
    }

    func featurePost(serverPostId _: Components.Schemas.PostID, featured _: Bool, local _: Bool) async throws {
        trap()
    }

    func removeComment(serverCommentId _: Components.Schemas.CommentID, removed _: Bool, reason _: String?) async throws {
        trap()
    }

    func distinguishComment(serverCommentId _: Components.Schemas.CommentID, distinguished _: Bool) async throws {
        trap()
    }

    func banFromCommunity(serverCommunityId _: Components.Schemas.CommunityID, serverPersonId _: Components.Schemas.PersonID, ban _: Bool, removeData _: Bool, reason _: String?) async throws {
        trap()
    }

    func resolveObject(query _: String) async throws -> ResolvedLemmyObject {
        trap()
    }
}

/// Minimal `AccountServiceType` stub whose `instanceCapabilities` is directly
/// configurable, so the test controls `AccountScope.capabilities` without
/// needing a persisted site version. Mirrors `FakeGatingAccountService` in
/// `InboxViewModelGatingTests.swift`.
@MainActor
private final class FakeSendGuardAccountService: AccountServiceType {
    let lemmyServiceDouble: RecordingSendLemmyService
    let capabilities: InstanceCapabilities

    init(lemmyServiceDouble: RecordingSendLemmyService, capabilities: InstanceCapabilities) {
        self.lemmyServiceDouble = lemmyServiceDouble
        self.capabilities = capabilities
    }

    func lemmyService(forAccountKeychainId _: String) -> LemmyServiceType {
        lemmyServiceDouble
    }

    func instanceCapabilities(forAccountKeychainId _: String) -> InstanceCapabilities {
        capabilities
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

    func defaultListingType(forAccountKeychainId _: String) -> Components.Schemas.ListingType {
        .All
    }

    func defaultSortType(forAccountKeychainId _: String) -> Components.Schemas.SortType {
        .Hot
    }

    func setDefaultSortType(_: Components.Schemas.SortType, forAccountKeychainId _: String) { }

    func refreshSiteInfoOnDemandIfNeeded(forAccountKeychainId _: String) { }

    func createFeed(type _: FeedType, forAccountKeychainId _: String) async throws -> FeedHandle {
        fatalError()
    }

    func defaultFeedHandle(forAccountKeychainId _: String) -> FeedHandle? {
        nil
    }
}

/// Records handled alert requests so the test can assert the guard surfaces
/// through the VM's existing failure-handling path (`alertService.handle`),
/// not a new mechanism. Mirrors `SpyAlertService` in
/// `PostDetailViewModelFetchTests.swift`.
private final class SpyAlertService: AlertServiceType, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [AlertHandlerRequest] = []
    var handledRequests: [AlertHandlerRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    func handle(_ error: Error, for request: AlertHandlerRequest) {
        lock.lock()
        _requests.append(request)
        lock.unlock()
    }

    func image(error _: ImageLoadingError, for _: URL) { }
}

/// No-op unread-count double - the send-guard test never touches unread
/// counts, so every method is inert rather than trapping.
@MainActor
private final class NoOpUnreadCountService: UnreadCountServiceType {
    var unreadCount: UnreadCount = .zero
    func refresh(accountKeychainId _: String) async { }
    func decrement(replies _: Int, mentions _: Int, privateMessages _: Int) { }
    func reset() { }
}

// MARK: - Tests

/// Covers the `DMThreadViewModel.send` capability backstop: a thread opened
/// (or left open) before `.privateMessages` becomes unavailable - e.g. the
/// home instance's version is re-detected mid-session - must not enqueue a
/// send, and the rejection must surface through the same
/// `alertService.handle` path an ordinary send failure uses. This mirrors the
/// server-side backstop `LemmyService.sendDirectMessage` already has via
/// `requireCapability(.privateMessages)`, but catches it one layer up so a
/// stale, still-enabled input bar never round-trips into the composer outbox
/// for content we already know will be rejected.
@MainActor
struct DMThreadViewModelSendGuardTests {
    private let keychainId = "kc-dm-send-guard-test"

    private func makeViewModel(
        capabilities: InstanceCapabilities,
        lemmyServiceDouble: RecordingSendLemmyService,
        alertService: SpyAlertService
    ) -> DMThreadViewModel {
        let appDatabase = try! AppDatabase.inMemory()
        let accountService = FakeSendGuardAccountService(
            lemmyServiceDouble: lemmyServiceDouble,
            capabilities: capabilities
        )
        let scope = AccountScope(accountKeychainId: keychainId, accountService: accountService)
        return DMThreadViewModel(
            accountScope: scope,
            appDatabase: appDatabase,
            correspondentId: Components.Schemas.PersonID(1),
            correspondentName: "someone",
            myPersonId: nil,
            alertService: alertService,
            unreadCountService: NoOpUnreadCountService()
        )
    }

    /// The core backstop: on a gated instance, `send` must never reach
    /// `sendDirectMessage` - the guard rejects before the fire-and-forget Task
    /// is even spawned - and the failure surfaces via `alertService.handle`.
    @Test
    func send_whenPrivateMessagesGated_performsNoServiceCallAndSurfacesFailure() async {
        let lemmyServiceDouble = RecordingSendLemmyService()
        let alertService = SpyAlertService()
        let gatedCapabilities = InstanceCapabilities.capabilities(
            software: .lemmy,
            version: LemmyVersion(parsing: "1.0.0-alpha.18")
        )
        let vm = makeViewModel(
            capabilities: gatedCapabilities,
            lemmyServiceDouble: lemmyServiceDouble,
            alertService: alertService
        )

        vm.send("hello")

        // The gated branch returns synchronously - no Task is ever spawned, so
        // there is nothing to await before asserting.
        let callCount = await lemmyServiceDouble.sendDirectMessageCallCount
        #expect(callCount == 0)
        #expect(alertService.handledRequests == [.sendPrivateMessage])
    }

    /// Guards against an inverted condition: an ungated instance must still
    /// send exactly as before this task, with no spurious failure surfaced.
    @Test
    func send_whenNotGated_callsServiceAndSurfacesNoFailure() async {
        let lemmyServiceDouble = RecordingSendLemmyService()
        let alertService = SpyAlertService()
        let vm = makeViewModel(
            capabilities: .allAvailable,
            lemmyServiceDouble: lemmyServiceDouble,
            alertService: alertService
        )

        vm.send("hello")

        // send() enqueues the network call on a detached Task; poll briefly
        // for it to land rather than assuming a fixed delay is enough.
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let count = await lemmyServiceDouble.sendDirectMessageCallCount
            if count > 0 { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let callCount = await lemmyServiceDouble.sendDirectMessageCallCount
        #expect(callCount == 1)
        #expect(alertService.handledRequests.isEmpty)
    }
}

// MARK: - Trap helper

/// Traps when an unexpected stub method is called in a fake.
private func trap(_ function: StaticString = #function) -> Never {
    fatalError("Unexpected call to \(function) in DMThreadViewModelSendGuardTests")
}
