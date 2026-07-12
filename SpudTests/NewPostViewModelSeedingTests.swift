//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudUtilKit
import Testing
@testable import Spud
@testable import SpudDataKit

// MARK: - Test doubles

/// `LemmyServiceType` fake with a functional, in-memory draft store (keyed
/// exactly like the real `ComposerOutboxService`-backed implementation), so a
/// test can seed a pre-existing draft and observe whether
/// `NewPostViewModel.loadExistingDraft()` overlays it. Every other method
/// traps — this VM under test never calls them.
private actor FakeComposerLemmyService: LemmyServiceType {
    private var drafts: [String: OutboundContentRecord] = [:]
    private var nextRowId: Int64 = 1

    /// Seeds a draft directly under `draftKey`, bypassing `saveDraft` — used
    /// to simulate a pre-existing draft left over from an earlier composer
    /// session.
    func seedDraft(draftKey: String, title: String?, body: String, url: String?) {
        drafts[draftKey] = OutboundContentRecord(
            id: nextRowId,
            clientToken: "seeded-token-\(nextRowId)",
            accountId: 1,
            kind: OutboundKind.post.rawValue,
            status: OutboundStatus.draft.rawValue,
            draftKey: draftKey,
            body: body,
            postServerId: nil,
            parentCommentServerId: nil,
            communityServerId: nil,
            title: title,
            url: url,
            nsfw: false,
            postType: Int64(NewPostType.text.rawValue),
            editCommentServerId: nil,
            editPostServerId: nil,
            recipientServerPersonId: nil,
            attempts: 0,
            lastError: nil,
            nextAttemptAt: nil,
            createdAt: Date().timeIntervalSince1970,
            updatedAt: Date().timeIntervalSince1970
        )
        nextRowId += 1
    }

    func loadDraft(draftKey: String) async throws -> OutboundContentRecord? {
        drafts[draftKey]
    }

    func saveDraft(_: OutboundDraftInput) async throws -> String {
        trap()
    }

    func submitDraft(clientToken _: String) async {
        trap()
    }

    func discardComposition(clientToken _: String) async {
        trap()
    }

    // MARK: Unused protocol stubs

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

    func fetchFeed(_: FeedHandle, pageCursor _: String?, showNsfw _: Bool) async throws -> String? {
        trap()
    }

    func fetchComments(serverPostId _: Lemmy.PostID, sortType _: Lemmy.CommentSortType) async throws {
        trap()
    }

    func outboxFailureEvents() async -> AsyncStream<OutboxFailure> {
        AsyncStream { $0.finish() }
    }

    func drainPendingOutbox() async {
        trap()
    }

    func retryComposition(clientToken _: String) async {
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

    func fetchReplies(unreadOnly _: Bool, page _: Int64) async throws -> [InboxCommentNotification] {
        trap()
    }

    func fetchMentions(unreadOnly _: Bool, page _: Int64) async throws -> [InboxCommentNotification] {
        trap()
    }

    func fetchPrivateMessages(unreadOnly _: Bool, pageCursor _: String?) async throws -> (messages: [IncomingPrivateMessage], nextCursor: String?) {
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

/// Minimal `AccountServiceType` stub — returns the given fake for every
/// keychain id, and reports a signed-in, capable account so `NewPostViewModel`
/// construction and `submit()` gating don't hit an early-out.
@MainActor
private final class FakeAccountServiceForComposer: AccountServiceType {
    let lemmyServiceFake: FakeComposerLemmyService

    init(lemmyService: FakeComposerLemmyService) {
        lemmyServiceFake = lemmyService
    }

    func lemmyService(forAccountKeychainId _: String) -> LemmyServiceType {
        lemmyServiceFake
    }

    func reminderService(forAccountKeychainId _: String) -> ReminderService {
        fatalError("reminderService not stubbed")
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
    func instanceActorId(forAccountKeychainId _: String) -> InstanceActorId? {
        nil
    }

    func instanceCapabilities(forAccountKeychainId _: String) -> InstanceCapabilities {
        .allAvailable
    }

    func refreshSiteInfoOnDemandIfNeeded(forAccountKeychainId _: String) { }

    func createFeed(type _: FeedType, forAccountKeychainId _: String) async throws -> FeedHandle {
        fatalError()
    }

    func defaultFeedHandle(forAccountKeychainId _: String) -> FeedHandle? {
        nil
    }
}

// MARK: - Tests

/// Covers the composer seeding un-gate: `NewPostViewModel.init` now seeds
/// `initialTitle`/`initialBody`/`initialUrl`/`initialNsfw` in new-post mode
/// too (previously edit-mode only), which is what lets a cross-post pre-fill
/// a brand-new post. The risk un-gating introduces is `loadExistingDraft()`
/// clobbering that seeded content with a stale nil-community draft — these
/// tests cover both the new behavior and that edit mode stays byte-identical.
@MainActor
struct NewPostViewModelSeedingTests {
    private let keychainId = "kc-cross-post-test"

    private func makeScope(lemmyService: FakeComposerLemmyService) -> AccountScope {
        let accountService = FakeAccountServiceForComposer(lemmyService: lemmyService)
        return AccountScope(accountKeychainId: keychainId, accountService: accountService)
    }

    // MARK: New-post mode seeding

    /// A cross-post's initial content is applied immediately at `init` —
    /// title, url, and a derived `.link` post type (a url makes it a link
    /// post, matching the edit-mode derivation).
    @Test
    func newPostMode_withInitialContent_seedsFieldsAtInit() {
        let scope = makeScope(lemmyService: FakeComposerLemmyService())
        let vm = NewPostViewModel(
            serverCommunityId: nil,
            initialCommunityName: nil,
            accountScope: scope,
            dependencies: FakeComposerDependencies(),
            initialTitle: "Cross-posted title",
            initialBody: "cross-posted from: https://lemmy.example/post/1",
            initialUrl: "https://example.com/article"
        )

        #expect(vm.titleText == "Cross-posted title")
        #expect(vm.bodyText == "cross-posted from: https://lemmy.example/post/1")
        #expect(vm.urlText == "https://example.com/article")
        #expect(vm.postType == .link)
    }

    /// The core regression this task guards against: seeding a cross-post's
    /// content into a fresh new-post composer (community = nil, same draft key
    /// a plain new post would use) must NOT be clobbered by a pre-existing
    /// nil-community draft once `loadExistingDraft()` runs.
    @Test
    func newPostMode_withInitialContent_notClobberedByPreExistingNilCommunityDraft() async {
        let lemmyService = FakeComposerLemmyService()
        await lemmyService.seedDraft(
            draftKey: OutboundContentRecord.postDraftKey(communityServerId: nil),
            title: "Stale abandoned draft",
            body: "stale draft body",
            url: nil
        )
        let scope = makeScope(lemmyService: lemmyService)
        let vm = NewPostViewModel(
            serverCommunityId: nil,
            initialCommunityName: nil,
            accountScope: scope,
            dependencies: FakeComposerDependencies(),
            initialTitle: "Cross-posted title",
            initialBody: "cross-posted from: https://lemmy.example/post/1",
            initialUrl: "https://example.com/article"
        )

        await vm.loadExistingDraft()

        #expect(vm.titleText == "Cross-posted title")
        #expect(vm.bodyText == "cross-posted from: https://lemmy.example/post/1")
        #expect(vm.urlText == "https://example.com/article")
    }

    /// Un-gating seeding must not break the pre-existing plain-new-post draft
    /// restore: with no initial content, a saved nil-community draft still
    /// overlays normally (Mail-style draft restore).
    @Test
    func newPostMode_withoutInitialContent_stillLoadsPreExistingDraft() async {
        let lemmyService = FakeComposerLemmyService()
        await lemmyService.seedDraft(
            draftKey: OutboundContentRecord.postDraftKey(communityServerId: nil),
            title: "Resumed draft title",
            body: "resumed draft body",
            url: nil
        )
        let scope = makeScope(lemmyService: lemmyService)
        let vm = NewPostViewModel(
            serverCommunityId: nil,
            initialCommunityName: nil,
            accountScope: scope,
            dependencies: FakeComposerDependencies()
        )

        // Fields start blank, matching the properties' own declared defaults.
        #expect(vm.titleText == "")

        await vm.loadExistingDraft()

        #expect(vm.titleText == "Resumed draft title")
        #expect(vm.bodyText == "resumed draft body")
    }

    // MARK: Edit mode unchanged

    /// Edit mode keeps its existing behavior byte-identical: it seeds from the
    /// post being edited, then unconditionally overlays a saved edit draft
    /// (keyed separately via `editPostDraftKey`, so it can't collide with a
    /// new-post draft) when one exists.
    @Test
    func editMode_seedsFromPost_thenOverlaysSavedEditDraftIfPresent() async {
        let lemmyService = FakeComposerLemmyService()
        await lemmyService.seedDraft(
            draftKey: OutboundContentRecord.editPostDraftKey(serverPostId: 42),
            title: "In-progress edit",
            body: "in-progress edit body",
            url: nil
        )
        let scope = makeScope(lemmyService: lemmyService)
        let vm = NewPostViewModel(
            serverCommunityId: Lemmy.CommunityID(7),
            initialCommunityName: "testcommunity",
            accountScope: scope,
            dependencies: FakeComposerDependencies(),
            editPostServerId: 42,
            initialTitle: "Original post title",
            initialBody: "original post body",
            initialUrl: nil
        )

        // Seeded from the post being edited, same as before this change.
        #expect(vm.titleText == "Original post title")

        await vm.loadExistingDraft()

        // Edit mode's own saved draft still overlays unconditionally.
        #expect(vm.titleText == "In-progress edit")
        #expect(vm.bodyText == "in-progress edit body")
    }

    /// Edit mode with no saved draft: the seeded post content stands
    /// unmodified after `loadExistingDraft()` finds nothing to overlay.
    @Test
    func editMode_noSavedDraft_keepsSeededPostContent() async {
        let scope = makeScope(lemmyService: FakeComposerLemmyService())
        let vm = NewPostViewModel(
            serverCommunityId: Lemmy.CommunityID(7),
            initialCommunityName: "testcommunity",
            accountScope: scope,
            dependencies: FakeComposerDependencies(),
            editPostServerId: 42,
            initialTitle: "Original post title",
            initialBody: "original post body",
            initialUrl: nil
        )

        await vm.loadExistingDraft()

        #expect(vm.titleText == "Original post title")
        #expect(vm.bodyText == "original post body")
    }
}

// MARK: - Dependencies fake

@MainActor
private struct FakeComposerDependencies: HasAccountService, HasAlertService {
    let accountService: AccountServiceType
    let alertService: AlertServiceType

    init() {
        accountService = FakeAccountServiceForComposer(lemmyService: FakeComposerLemmyService())
        alertService = AlertService()
    }
}

// MARK: - Trap helper

/// Traps when an unexpected stub method is called in a fake.
private func trap(_ function: StaticString = #function) -> Never {
    fatalError("Unexpected call to \(function) in NewPostViewModelSeedingTests")
}
