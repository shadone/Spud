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

/// Records calls to the three inbox fetch methods `InboxViewModel.loadAll()`
/// drives. All other `LemmyServiceType` requirements trap - none of them
/// should ever be reached from a gating test. Mirrors the shape of
/// `SpySaveProfileService` in `EditProfileViewModelBannerTests.swift`.
private actor RecordingInboxLemmyService: LemmyServiceType {
    private(set) var fetchRepliesCallCount = 0
    private(set) var fetchMentionsCallCount = 0
    private(set) var fetchPrivateMessagesCallCount = 0

    func fetchReplies(unreadOnly _: Bool, page _: Int64) async throws -> Lemmy.GetRepliesResponse {
        fetchRepliesCallCount += 1
        return Lemmy.GetRepliesResponse(replies: [])
    }

    func fetchMentions(unreadOnly _: Bool, page _: Int64) async throws -> Lemmy.GetPersonMentionsResponse {
        fetchMentionsCallCount += 1
        return Lemmy.GetPersonMentionsResponse(mentions: [])
    }

    func fetchPrivateMessages(unreadOnly _: Bool, page _: Int64) async throws -> [IncomingPrivateMessage] {
        fetchPrivateMessagesCallCount += 1
        return []
    }

    // MARK: Unused protocol stubs

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
        avatar _: String?,
        banner _: String?,
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

    func sendDirectMessage(body _: String, recipientServerPersonId _: Int64) async throws -> String {
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

    func unreadCount() async throws -> UnreadCount {
        trap()
    }

    func markReplyAsRead(commentReplyId _: Lemmy.CommentReplyID, read _: Bool) async throws {
        trap()
    }

    func markMentionAsRead(personMentionId _: Lemmy.PersonMentionID, read _: Bool) async throws {
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

/// Records `refresh` calls without touching a `LemmyServiceType` at all, so
/// this fake stays decoupled from `RecordingInboxLemmyService` above - the
/// gating test only asserts on the inbox-fetch call counts.
@MainActor
private final class SpyUnreadCountService: UnreadCountServiceType {
    private(set) var refreshCallCount = 0
    var unreadCount: UnreadCount = .zero

    func refresh(accountKeychainId _: String) async {
        refreshCallCount += 1
    }

    func decrement(replies _: Int, mentions _: Int, privateMessages _: Int) { }
    func reset() { }
}

/// Minimal `AccountServiceType` stub whose `instanceCapabilities` and
/// `instanceActorId` are directly configurable, so the gating test controls
/// `AccountScope.capabilities` without needing a persisted site version.
/// Mirrors `FakeAccountService` in `EditProfileViewModelBannerTests.swift`.
@MainActor
private final class FakeGatingAccountService: AccountServiceType {
    let lemmyServiceDouble: RecordingInboxLemmyService
    let capabilities: InstanceCapabilities
    let instance: InstanceActorId?

    init(lemmyServiceDouble: RecordingInboxLemmyService, capabilities: InstanceCapabilities, instance: InstanceActorId?) {
        self.lemmyServiceDouble = lemmyServiceDouble
        self.capabilities = capabilities
        self.instance = instance
    }

    func lemmyService(forAccountKeychainId _: String) -> LemmyServiceType {
        lemmyServiceDouble
    }

    func instanceCapabilities(forAccountKeychainId _: String) -> InstanceCapabilities {
        capabilities
    }

    func instanceActorId(forAccountKeychainId _: String) -> InstanceActorId? {
        instance
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

// MARK: - Tests

@MainActor
struct InboxViewModelGatingTests {
    private let keychainId = "kc-inbox-gating-test"

    private func makeViewModel(
        capabilities: InstanceCapabilities,
        instance: InstanceActorId?,
        lemmyServiceDouble: RecordingInboxLemmyService,
        unreadCountService: SpyUnreadCountService
    ) -> InboxViewModel {
        let appDatabase = try! AppDatabase.inMemory()
        let accountService = FakeGatingAccountService(
            lemmyServiceDouble: lemmyServiceDouble,
            capabilities: capabilities,
            instance: instance
        )
        let scope = AccountScope(accountKeychainId: keychainId, accountService: accountService)
        return InboxViewModel(
            accountScope: scope,
            appDatabase: appDatabase,
            isSignedIn: true,
            myPersonId: nil,
            alertService: AlertService(),
            unreadCountService: unreadCountService
        )
    }

    /// The core gating requirement: on a Lemmy 1.0 (v3-shim) instance, none of
    /// the three inbox fetches ever reach the service, and the VM exposes the
    /// gated state (host + flag) the view controller renders instead.
    @Test
    func loadAll_whenInboxGated_performsNoServiceCallsAndExposesGatedState() async throws {
        let lemmyServiceDouble = RecordingInboxLemmyService()
        let unreadCountService = SpyUnreadCountService()
        let gatedCapabilities = InstanceCapabilities.capabilities(
            software: .lemmy,
            version: LemmyVersion(parsing: "1.0.0-alpha.18")
        )
        let instance = try #require(InstanceActorId(from: "https://lemmy.example.com"))
        let vm = makeViewModel(
            capabilities: gatedCapabilities,
            instance: instance,
            lemmyServiceDouble: lemmyServiceDouble,
            unreadCountService: unreadCountService
        )

        vm.loadAll()

        // The gated branch returns synchronously - no Task is ever spawned, so
        // there is nothing to await before asserting.
        let fetchReplies = await lemmyServiceDouble.fetchRepliesCallCount
        let fetchMentions = await lemmyServiceDouble.fetchMentionsCallCount
        let fetchPrivateMessages = await lemmyServiceDouble.fetchPrivateMessagesCallCount
        #expect(fetchReplies == 0)
        #expect(fetchMentions == 0)
        #expect(fetchPrivateMessages == 0)
        #expect(unreadCountService.refreshCallCount == 0)

        #expect(vm.isInboxGated)
        #expect(vm.gatedHost == "lemmy.example.com")
        #expect(vm.repliesPhase == .loaded)
        #expect(vm.mentionsPhase == .loaded)
        #expect(vm.messagesPhase == .loaded)
        #expect(vm.replies.isEmpty)
        #expect(vm.mentions.isEmpty)
        #expect(vm.conversations.isEmpty)
    }

    /// Guards against an inverted condition: an ungated instance must still
    /// fetch all three scopes exactly as before this task.
    @Test
    func loadAll_whenNotGated_fetchesAllThreeScopes() async {
        let lemmyServiceDouble = RecordingInboxLemmyService()
        let unreadCountService = SpyUnreadCountService()
        let vm = makeViewModel(
            capabilities: .allAvailable,
            instance: nil,
            lemmyServiceDouble: lemmyServiceDouble,
            unreadCountService: unreadCountService
        )

        vm.loadAll()
        // `loadReplies()`/`loadMentions()` run their fetch in detached Tasks;
        // poll briefly for both call counts to land rather than assuming a
        // fixed delay is enough.
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let replies = await lemmyServiceDouble.fetchRepliesCallCount
            let mentions = await lemmyServiceDouble.fetchMentionsCallCount
            if replies > 0, mentions > 0 { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let fetchReplies = await lemmyServiceDouble.fetchRepliesCallCount
        let fetchMentions = await lemmyServiceDouble.fetchMentionsCallCount
        #expect(fetchReplies == 1)
        #expect(fetchMentions == 1)
        #expect(!vm.isInboxGated)
        #expect(vm.gatedHost == nil)
    }
}

// MARK: - Trap helper

/// Traps when an unexpected stub method is called in a fake.
private func trap(_ function: StaticString = #function) -> Never {
    fatalError("Unexpected call to \(function) in InboxViewModelGatingTests")
}
