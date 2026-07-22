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

/// Records `setSubscribed` calls. All other `LemmyServiceType` requirements
/// trap — none of them should ever be reached from `toggleSubscribe`. Mirrors
/// the shape of `SpySaveProfileService` in `EditProfileViewModelBannerTests.swift`.
private actor SpySubscribeLemmyService: LemmyServiceType {
    struct SetSubscribedCall: Equatable {
        let serverCommunityId: Lemmy.CommunityID
        let subscribed: Bool
    }

    private(set) var setSubscribedCalls: [SetSubscribedCall] = []

    func setSubscribed(serverCommunityId: Lemmy.CommunityID, subscribed: Bool) async throws {
        setSubscribedCalls.append(SetSubscribedCall(serverCommunityId: serverCommunityId, subscribed: subscribed))
    }

    // MARK: Unused protocol stubs

    func fetchFeed(_: FeedHandle, pageCursor _: String?, showNsfw _: Bool) async throws -> String? {
        trap()
    }

    func fetchComments(serverPostId _: Lemmy.PostID, sortType _: Lemmy.CommentSortType, maxPages _: Int) async throws -> CommentFetchCompletion {
        trap()
    }

    func fetchMoreComments(
        serverPostId _: Lemmy.PostID,
        parentServerId _: Int64,
        sortType _: Lemmy.CommentSortType
    ) async throws {
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

/// Minimal `AccountServiceType` stub — returns our spy for every keychain id and
/// a fixed home instance so `AccountScope.instanceActorId` resolves.
@MainActor
private final class FakeMetaSectionAccountService: AccountServiceType {
    let lemmyServiceSpy: SpySubscribeLemmyService
    let instance: InstanceActorId?

    init(lemmyServiceSpy: SpySubscribeLemmyService, instance: InstanceActorId?) {
        self.lemmyServiceSpy = lemmyServiceSpy
        self.instance = instance
    }

    func lemmyService(forAccountKeychainId _: String) -> LemmyServiceType {
        lemmyServiceSpy
    }

    func reminderService(forAccountKeychainId _: String) -> ReminderService {
        fatalError("reminderService not stubbed")
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

/// Exercises the "About <instance>" meta-section wiring added to
/// `SubscriptionsViewModel`: the favourite action round-trips against
/// `AppDatabase`, and the subscribe action forwards through the account's
/// `LemmyService`. Seeding mirrors
/// `SpudDataKitTests/AppDatabase/InstanceMetaCommunityQueriesTests.swift`.
@MainActor
struct SubscriptionsMetaSectionViewModelTests {
    private let keychainId = "kc-meta-section-test"
    private let communityActorId = "https://tchncs.de/c/meta"
    private let serverCommunityId: Int64 = 42

    /// `AccountRecord.siteId` is a NOT NULL foreign key to `site`, which in turn
    /// has a NOT NULL foreign key to `instance` — so seeding a bare account
    /// requires standing up an instance and a site first (mirrors
    /// `InstanceMetaCommunityQueriesTests.makeAccount`).
    private func makeAccount(appDatabase: AppDatabase) throws -> Int64 {
        try appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://tchncs.de")
            try instance.insert(db)

            var site = try SiteRecord(instanceId: #require(instance.id))
            try site.insert(db)

            var account = try AccountRecord(
                siteId: #require(site.id),
                accountKeychainId: keychainId
            )
            try account.insert(db)
            return try #require(account.id)
        }
    }

    private func insertCommunity(appDatabase: AppDatabase, accountId: Int64) throws {
        try appDatabase.writer.write { db in
            var c = CommunityRecord(
                accountId: accountId, communityId: serverCommunityId, name: "meta", title: "Meta",
                actorId: communityActorId, descriptionText: nil, iconUrl: nil, bannerUrl: nil,
                isHidden: false, isLocal: true, isNsfw: false,
                isPostingRestrictedToMods: false, isRemoved: false,
                subscribedState: CommunitySubscribedState.notSubscribed.rawValue, numberOfSubscribers: 0,
                numberOfPosts: 0, numberOfComments: 0, communityCreatedDate: nil,
                communityUpdatedDate: nil, createdAt: Date(), updatedAt: Date()
            )
            try c.insert(db)
        }
    }

    /// Builds a VM wired to a fresh in-memory DB seeded with one cached meta
    /// community, plus the given `LemmyServiceType` double.
    private func makeViewModel(
        appDatabase: AppDatabase, accountId: Int64, lemmyServiceSpy: SpySubscribeLemmyService
    ) -> SubscriptionsViewModel {
        let accountService = FakeMetaSectionAccountService(
            lemmyServiceSpy: lemmyServiceSpy,
            instance: InstanceActorId(from: "https://tchncs.de")
        )
        let scope = AccountScope(accountKeychainId: keychainId, accountService: accountService)
        return SubscriptionsViewModel(
            accountRowId: accountId,
            isSignedIn: true,
            appDatabase: appDatabase,
            accountScope: scope,
            metaCommunityService: nil,
            onFeedRequested: { _ in },
            onExploreRequested: { }
        )
    }

    @Test
    func toggleFavorite_roundTripsThroughAppDatabase() throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try makeAccount(appDatabase: appDatabase)
        try insertCommunity(appDatabase: appDatabase, accountId: accountId)
        appDatabase.replaceMetaCommunitiesSync(
            forAccountId: accountId, instanceHost: "tchncs.de",
            entries: [.init(communityActorId: communityActorId, confidence: .high, reason: .strongKeyword)]
        )

        let vm = makeViewModel(appDatabase: appDatabase, accountId: accountId, lemmyServiceSpy: SpySubscribeLemmyService())

        let notFavorited = MetaCommunityListItem(
            id: serverCommunityId, name: "meta", title: "Meta", communityActorId: communityActorId,
            iconUrl: nil, confidence: .high, subscribedState: .notSubscribed, isFavorite: false
        )
        #expect(!appDatabase.isCommunityFavoritedSync(forKeychainId: keychainId, communityActorId: communityActorId))

        vm.toggleFavorite(notFavorited)
        #expect(appDatabase.isCommunityFavoritedSync(forKeychainId: keychainId, communityActorId: communityActorId))

        let favorited = MetaCommunityListItem(
            id: serverCommunityId, name: "meta", title: "Meta", communityActorId: communityActorId,
            iconUrl: nil, confidence: .high, subscribedState: .notSubscribed, isFavorite: true
        )
        vm.toggleFavorite(favorited)
        #expect(!appDatabase.isCommunityFavoritedSync(forKeychainId: keychainId, communityActorId: communityActorId))
    }

    /// `toggleSubscribe` forwards to the account's `LemmyService.setSubscribed`,
    /// flipping the requested state based on the item's current
    /// `subscribedState` — proving the subscribe half of the wiring, not just
    /// the favourite round-trip.
    @Test
    func toggleSubscribe_notSubscribed_callsSetSubscribedTrue() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let accountId = try makeAccount(appDatabase: appDatabase)
        try insertCommunity(appDatabase: appDatabase, accountId: accountId)
        appDatabase.replaceMetaCommunitiesSync(
            forAccountId: accountId, instanceHost: "tchncs.de",
            entries: [.init(communityActorId: communityActorId, confidence: .high, reason: .strongKeyword)]
        )

        let spy = SpySubscribeLemmyService()
        let vm = makeViewModel(appDatabase: appDatabase, accountId: accountId, lemmyServiceSpy: spy)

        let item = MetaCommunityListItem(
            id: serverCommunityId, name: "meta", title: "Meta", communityActorId: communityActorId,
            iconUrl: nil, confidence: .high, subscribedState: .notSubscribed, isFavorite: false
        )
        vm.toggleSubscribe(item)

        // `toggleSubscribe` fires the network call from a detached `Task`; poll
        // briefly rather than assuming a fixed delay is enough.
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if await !spy.setSubscribedCalls.isEmpty { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let calls = await spy.setSubscribedCalls
        try #require(calls.count == 1)
        #expect(calls[0].serverCommunityId == Lemmy.CommunityID(serverCommunityId))
        #expect(calls[0].subscribed)
    }
}

// MARK: - Trap helper

/// Traps when an unexpected stub method is called in a fake.
private func trap(_ function: StaticString = #function) -> Never {
    fatalError("Unexpected call to \(function) in SubscriptionsMetaSectionViewModelTests")
}
