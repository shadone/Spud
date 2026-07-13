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
import UIKit
@testable import Spud

// MARK: - Test doubles

/// Records the arguments passed to `saveProfile`. All other methods trap.
private actor SpySaveProfileService: LemmyServiceType {
    struct SaveProfileCall {
        let displayName: String?
        let bio: String?
        let avatar: ProfileImageEdit
        let banner: ProfileImageEdit
        let showScores: Bool
        let showBotAccounts: Bool
        let showReadPosts: Bool
        let showAvatars: Bool
        let defaultListingType: Lemmy.ListingType
    }

    private(set) var saveProfileCalls: [SaveProfileCall] = []
    /// Counts direct `uploadImage` calls. The editor must NOT upload at pick time
    /// anymore (that orphaned a pict-rs file); the single upload happens server-side
    /// inside `saveProfile`, which this spy records separately via `saveProfileCalls`.
    private(set) var uploadImageCallCount = 0
    var uploadImageResult: Result<URL, Error> = .success(URL(string: "https://example.com/banner.jpg")!)

    func saveProfile(
        displayName: String?,
        bio: String?,
        avatar: ProfileImageEdit,
        banner: ProfileImageEdit,
        showScores: Bool,
        showBotAccounts: Bool,
        showReadPosts: Bool,
        showAvatars: Bool,
        defaultListingType: Lemmy.ListingType
    ) async throws {
        saveProfileCalls.append(SaveProfileCall(
            displayName: displayName,
            bio: bio,
            avatar: avatar,
            banner: banner,
            showScores: showScores,
            showBotAccounts: showBotAccounts,
            showReadPosts: showReadPosts,
            showAvatars: showAvatars,
            defaultListingType: defaultListingType
        ))
    }

    func uploadImage(imageData _: Data, fileName _: String, mimeType _: String) async throws -> URL {
        uploadImageCallCount += 1
        return try uploadImageResult.get()
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

    func fetchPersonInfo(serverPersonId _: Lemmy.PersonID) async throws {
        trap()
    }

    func fetchPersonContent(serverPersonId _: Lemmy.PersonID, sort _: Lemmy.SortType, page _: Int64) async throws -> PersonContentPage {
        trap()
    }

    func fetchFeed(_: FeedHandle, pageCursor _: String?, showNsfw _: Bool) async throws -> String? {
        trap()
    }

    func fetchComments(serverPostId _: Lemmy.PostID, sortType _: Lemmy.CommentSortType) async throws {
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

/// Minimal `AccountServiceType` stub — returns our spy for every keychain id.
@MainActor
private final class FakeAccountService: AccountServiceType {
    let lemmyServiceSpy: SpySaveProfileService

    init(lemmyServiceSpy: SpySaveProfileService) {
        self.lemmyServiceSpy = lemmyServiceSpy
    }

    func lemmyService(forAccountKeychainId _: String) -> LemmyServiceType {
        lemmyServiceSpy
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
    func reauthenticate(keychainId _: String, username _: String, password _: String, totp2faToken _: String?) async throws { }
    func username(forAccountKeychainId _: String) -> String? {
        nil
    }

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

@MainActor
struct EditProfileViewModelBannerTests {
    private let keychainId = "kc-banner-test"

    // MARK: Helpers

    /// Builds a VM wired to the given spy, backed by an empty in-memory DB.
    /// No account row is seeded — `accountEditableProfileSync` returns nil and
    /// every VM field starts at its default value.
    private func makeViewModel(spy: SpySaveProfileService) -> EditProfileViewModel {
        let appDatabase = try! AppDatabase.inMemory()
        let accountService = FakeAccountService(lemmyServiceSpy: spy)
        let scope = AccountScope(accountKeychainId: keychainId, accountService: accountService)
        return EditProfileViewModel(
            accountScope: scope,
            appDatabase: appDatabase,
            accountService: accountService,
            onSaved: { }
        )
    }

    // MARK: Tests

    /// `removeBanner()` marks the banner as edited with no pending bytes, so
    /// `save()` must forward `banner: .removed` (which issues the server-side
    /// banner-remove push).
    @Test
    func removeBanner_thenSave_forwardsBannerRemoved() async throws {
        let spy = SpySaveProfileService()
        let vm = makeViewModel(spy: spy)

        vm.removeBanner()
        await vm.save()

        let calls = await spy.saveProfileCalls
        try #require(calls.count == 1)
        #expect(calls[0].banner == .removed)
    }

    /// Picking a banner records the encoded bytes locally and drives an instant
    /// local preview WITHOUT any pick-time upload; `save()` then forwards
    /// `banner: .set` carrying those bytes (the single, server-side push). The
    /// direct `uploadImage` endpoint is never hit — the old pick-time upload that
    /// orphaned a pict-rs file is gone.
    @Test
    func pickBanner_thenSave_uploadsOnceAtSaveNotAtPick() async throws {
        let spy = SpySaveProfileService()
        let vm = makeViewModel(spy: spy)

        vm.pickBanner(imageData: Self.minimalJpeg)

        // Pick drives the local preview and does NOT upload.
        #expect(vm.pickedBannerImage != nil)
        #expect(await spy.uploadImageCallCount == 0)

        await vm.save()

        // The single upload is carried by the save push, as `.set` bytes.
        let calls = await spy.saveProfileCalls
        try #require(calls.count == 1)
        guard case let .set(imageData, fileName, contentType) = calls[0].banner else {
            Issue.record("expected banner .set, got \(calls[0].banner)")
            return
        }
        #expect(!imageData.isEmpty)
        #expect(fileName.hasPrefix("banner-"))
        #expect(contentType == "image/jpeg")
        // Still no direct uploadImage call — saveProfile carries the push.
        #expect(await spy.uploadImageCallCount == 0)
    }

    /// When the banner is not touched, `save()` must pass `banner: .unchanged` so
    /// the server value is left alone (gating mirrors the avatar logic exactly).
    @Test
    func noChangeToBanner_save_forwardsBannerUnchanged() async throws {
        let spy = SpySaveProfileService()
        let vm = makeViewModel(spy: spy)

        // Do NOT call removeBanner() or pickBanner — banner is untouched.
        await vm.save()

        let calls = await spy.saveProfileCalls
        try #require(calls.count == 1)
        #expect(calls[0].banner == .unchanged)
    }

    // MARK: Avatar

    /// `removeAvatar()` marks the avatar as edited with no pending bytes, so
    /// `save()` must forward `avatar: .removed` (issuing the avatar-remove push).
    @Test
    func removeAvatar_thenSave_forwardsAvatarRemoved() async throws {
        let spy = SpySaveProfileService()
        let vm = makeViewModel(spy: spy)

        vm.removeAvatar()
        await vm.save()

        let calls = await spy.saveProfileCalls
        try #require(calls.count == 1)
        #expect(calls[0].avatar == .removed)
    }

    /// Picking an avatar retains the encoded bytes and drives an instant local
    /// preview with no pick-time upload; `save()` forwards `avatar: .set` carrying
    /// those bytes (the single server-side push).
    @Test
    func pickAvatar_thenSave_uploadsOnceAtSaveNotAtPick() async throws {
        let spy = SpySaveProfileService()
        let vm = makeViewModel(spy: spy)

        vm.pickAvatar(imageData: Self.minimalJpeg)

        #expect(vm.pickedAvatarImage != nil)
        #expect(await spy.uploadImageCallCount == 0)

        await vm.save()

        let calls = await spy.saveProfileCalls
        try #require(calls.count == 1)
        guard case let .set(imageData, fileName, contentType) = calls[0].avatar else {
            Issue.record("expected avatar .set, got \(calls[0].avatar)")
            return
        }
        #expect(!imageData.isEmpty)
        #expect(fileName.hasPrefix("avatar-"))
        #expect(contentType == "image/jpeg")
        #expect(await spy.uploadImageCallCount == 0)
    }

    /// When the avatar is not touched, `save()` must pass `avatar: .unchanged`.
    @Test
    func noChangeToAvatar_save_forwardsAvatarUnchanged() async throws {
        let spy = SpySaveProfileService()
        let vm = makeViewModel(spy: spy)

        await vm.save()

        let calls = await spy.saveProfileCalls
        try #require(calls.count == 1)
        #expect(calls[0].avatar == .unchanged)
    }

    // MARK: Fixtures

    /// A 1x1 red JPEG produced at runtime by `UIGraphicsImageRenderer`, which
    /// guarantees `UIImage(data:)` round-trips successfully inside `pickBanner` /
    /// `pickAvatar`.
    @MainActor
    private static var minimalJpeg: Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }
}

// MARK: - Trap helper

/// Traps when an unexpected stub method is called in a fake.
private func trap(_ function: StaticString = #function) -> Never {
    fatalError("Unexpected call to \(function) in EditProfileViewModelBannerTests")
}
