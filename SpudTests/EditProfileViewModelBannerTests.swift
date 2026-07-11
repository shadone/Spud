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
        let avatar: String?
        let banner: String?
        let showScores: Bool
        let showBotAccounts: Bool
        let showReadPosts: Bool
        let showAvatars: Bool
        let defaultListingType: Lemmy.ListingType
    }

    private(set) var saveProfileCalls: [SaveProfileCall] = []
    var uploadImageResult: Result<URL, Error> = .success(URL(string: "https://example.com/banner.jpg")!)

    func saveProfile(
        displayName: String?,
        bio: String?,
        avatar: String?,
        banner: String?,
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
        try uploadImageResult.get()
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

    func fetchPrivateMessages(unreadOnly _: Bool, page _: Int64) async throws -> [IncomingPrivateMessage] {
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

    // MARK: Mutation helper (called from outside the actor)

    func setUploadImageResult(_ result: Result<URL, Error>) {
        uploadImageResult = result
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

    /// `removeBanner()` marks the banner as edited, so `save()` must forward
    /// `banner: ""` (empty string = clear the server-side banner).
    @Test
    func removeBanner_thenSave_forwardsBannerEmptyString() async throws {
        let spy = SpySaveProfileService()
        let vm = makeViewModel(spy: spy)

        vm.removeBanner()
        await vm.save()

        let calls = await spy.saveProfileCalls
        try #require(calls.count == 1)
        #expect(calls[0].banner == "")
    }

    /// `uploadBanner` marks the banner as edited and stores the URL, so
    /// `save()` must forward the URL string as `banner`.
    @Test
    func uploadBanner_thenSave_forwardsBannerUrl() async throws {
        let uploadedUrl = try #require(URL(string: "https://example.com/my-banner.jpg"))
        let spy = SpySaveProfileService()
        await spy.setUploadImageResult(.success(uploadedUrl))

        let vm = makeViewModel(spy: spy)
        await vm.uploadBanner(imageData: Self.minimalJpeg)
        await vm.save()

        let calls = await spy.saveProfileCalls
        try #require(calls.count == 1)
        #expect(calls[0].banner == uploadedUrl.absoluteString)
    }

    /// When the banner is not touched, `save()` must pass `banner: nil` so the
    /// server value is left unchanged (gating mirrors the avatar logic exactly).
    @Test
    func noChangeToBanner_save_forwardsBannerNil() async throws {
        let spy = SpySaveProfileService()
        let vm = makeViewModel(spy: spy)

        // Do NOT call removeBanner() or uploadBanner — banner is untouched.
        await vm.save()

        let calls = await spy.saveProfileCalls
        try #require(calls.count == 1)
        #expect(calls[0].banner == nil)
    }

    // MARK: Fixtures

    /// A 1x1 red JPEG produced at runtime by `UIGraphicsImageRenderer`, which
    /// guarantees `UIImage(data:)` round-trips successfully inside `uploadBanner`.
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
