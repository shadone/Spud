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

// MARK: - SchedulerService

// SchedulerService has no test seam; coverage is integration-only.
// The timer-driven tick loop fires private async methods and there is no
// injectable seam for unit tests.

// MARK: - UnreadCountService

/// Minimal `@MainActor` fake for `AccountServiceType` that covers only the two
/// methods `UnreadCountService.refresh` calls.
///
/// - `isSignedOut` returns `false` (signed-in account) by default.
/// - `lemmyService(forAccountKeychainId:)` returns the injected `LemmyServiceType` stub.
/// - `instanceActorId(forAccountKeychainId:)` returns a fake instance actor id.
@MainActor
private final class StubAccountService: AccountServiceType {
    let stubbedIsSignedOut: Bool
    let stubbedLemmyService: any LemmyServiceType

    init(isSignedOut: Bool = false, lemmyService: any LemmyServiceType) {
        stubbedIsSignedOut = isSignedOut
        stubbedLemmyService = lemmyService
    }

    func isSignedOut(forAccountKeychainId _: String) -> Bool {
        stubbedIsSignedOut
    }

    func lemmyService(forAccountKeychainId _: String) -> LemmyServiceType {
        stubbedLemmyService
    }

    func instanceActorId(forAccountKeychainId _: String) -> InstanceActorId? {
        InstanceActorId(from: "https://lemmy.test")
    }

    func instanceCapabilities(forAccountKeychainId _: String) -> InstanceCapabilities {
        .allAvailable
    }

    // MARK: - Unused protocol requirements

    func accountForSignedOut(forInstance _: InstanceActorId, isServiceAccount _: Bool) -> String {
        ""
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
        fatalError("not used in tests")
    }
}

/// Minimal `LemmyServiceType` stub whose `unreadCount()` returns a fixed value or throws.
private actor StubLemmyService: LemmyServiceType {
    enum Mode {
        case success(UnreadCount)
        case failure(any Error)
    }

    let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    func unreadCount() async throws -> UnreadCount {
        switch mode {
        case let .success(count): return count
        case let .failure(error): throw error
        }
    }

    // MARK: - Unused protocol requirements (trap if hit)

    func fetchSiteInfo() async throws {
        unreachable()
    }

    func getSiteInfo() async throws -> LemmyKit.SiteInfo {
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

    func fetchPersonContent(serverPersonId _: Lemmy.PersonID, sort _: Lemmy.SortType, page _: Int64) async throws -> PersonContentPage {
        unreachable()
    }

    func fetchCommunityInfo(serverCommunityId _: Lemmy.CommunityID) async throws {
        unreachable()
    }

    func fetchCommunityInfo(communityName _: String) async throws -> Lemmy.CommunityID {
        unreachable()
    }

    func search(query _: String, type _: Lemmy.SearchType, sort _: Lemmy.SortType, listingType _: Lemmy.ListingType, page _: Int64) async throws -> LemmyKit.SearchResults {
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

    func fetchPrivateMessages(unreadOnly _: Bool, page _: Int64) async throws -> [IncomingPrivateMessage] {
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
    fatalError("StubLemmyService.\(function) is not implemented for BackgroundTaskDiagnosticsTests")
}

/// Tests that `UnreadCountService.refresh` emits the expected diagnostic events.
///
/// The suite is `@MainActor` and serialized because `UnreadCountService` is
/// `@MainActor` and the stub `AccountServiceType` is `@MainActor`-bound.
@MainActor
@Suite(.serialized)
struct UnreadCountServiceDiagnosticsTests {
    private let keychainId = "kc-diag-1"

    // MARK: - Success path

    @Test
    func refreshSuccess_emitsStartAndFinish() async throws {
        let spy = DiagnosticLogSpy()
        let lemmy = StubLemmyService(mode: .success(UnreadCount(replies: 3, mentions: 1, privateMessages: 2)))
        let accountService = StubAccountService(lemmyService: lemmy)
        let service = UnreadCountService(accountService: accountService, diagnostics: spy)

        await service.refresh(accountKeychainId: keychainId)

        let startEvents = spy.events(matching: "refresh.start")
        #expect(startEvents.count == 1, "expected exactly one refresh.start event")
        let startEvent = try #require(startEvents.first)
        #expect(startEvent.category == .unread)
        #expect(startEvent.level == .info)
        #expect(startEvent.instance == "lemmy.test")

        let finishEvents = spy.events(matching: "refresh.finish")
        #expect(finishEvents.count == 1, "expected exactly one refresh.finish event")
        let finishEvent = try #require(finishEvents.first)
        #expect(finishEvent.category == .unread)
        #expect(finishEvent.level == .info)
        #expect(finishEvent.instance == "lemmy.test")
        #expect(finishEvent.metadata?["unreadCount"] == "6")

        // No failure event on success.
        #expect(spy.events(matching: "refresh.failed").isEmpty)
    }

    // MARK: - Failure path

    @Test
    func refreshFailure_emitsStartAndFailed() async throws {
        let spy = DiagnosticLogSpy()
        let error = LemmyApiError.unknownServerError(httpStatusCode: 403, error: nil)
        let lemmy = StubLemmyService(mode: .failure(error))
        let accountService = StubAccountService(lemmyService: lemmy)
        let service = UnreadCountService(accountService: accountService, diagnostics: spy)

        await service.refresh(accountKeychainId: keychainId)

        let startEvents = spy.events(matching: "refresh.start")
        #expect(startEvents.count == 1, "expected exactly one refresh.start event")

        let failedEvents = spy.events(matching: "refresh.failed")
        #expect(failedEvents.count == 1, "expected exactly one refresh.failed event")
        let failedEvent = try #require(failedEvents.first)
        #expect(failedEvent.category == .unread)
        #expect(failedEvent.level == .error)
        #expect(failedEvent.instance == "lemmy.test")
        #expect(failedEvent.metadata?["httpStatus"] == "403")

        // No finish event on failure.
        #expect(spy.events(matching: "refresh.finish").isEmpty)
    }
}

// MARK: - OfflineDownloadService

/// Tests that `OfflineDownloadService.download` emits the expected diagnostic events.
@Suite(.serialized)
struct OfflineDownloadServiceDiagnosticsTests {
    private let appDatabase: AppDatabase
    private let accountId: Int64
    private let siteId: Int64
    private let communityId: Int64
    private let personId: Int64

    private let feed = FeedHandle(
        feedKey: "diag-feed-1",
        feedType: .frontpage(listingType: .All, sortType: .Hot)
    )
    private let commentSort = Lemmy.CommentSortType.Hot

    init() async throws {
        appDatabase = try AppDatabase.inMemory()
        let seeded = try await Self.seedGraph(appDatabase)
        accountId = seeded.accountId
        siteId = seeded.siteId
        communityId = seeded.communityId
        personId = seeded.personId
    }

    private static func seedGraph(
        _ appDatabase: AppDatabase
    ) async throws -> (accountId: Int64, siteId: Int64, communityId: Int64, personId: Int64) {
        let now = Date()
        return try await appDatabase.writer.write { db in
            try db.execute(
                sql: "INSERT INTO instance (actorId, createdAt) VALUES (?, ?)",
                arguments: ["https://diag.instance", now]
            )
            let instanceId = db.lastInsertedRowID
            try db.execute(
                sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, ?, ?)",
                arguments: [instanceId, now, now]
            )
            let siteId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO account
                        (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt)
                    VALUES (?, 'kc-diag-dl-1', 1, 0, 0, ?, ?)
                    """,
                arguments: [siteId, now, now]
            )
            let accountId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO person
                        (siteId, personId, isAdmin, isBanned, isBotAccount, isDeleted, isLocal,
                         numberOfPosts, numberOfComments, createdAt, updatedAt)
                    VALUES (?, 1, 0, 0, 0, 0, 1, 0, 0, ?, ?)
                    """,
                arguments: [siteId, now, now]
            )
            let personId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO community
                        (accountId, communityId, isHidden, isLocal, isNsfw, isPostingRestrictedToMods,
                         isRemoved, subscribedState, numberOfSubscribers, numberOfPosts,
                         numberOfComments, createdAt, updatedAt)
                    VALUES (?, 1, 0, 1, 0, 0, 0, 'NotSubscribed', 0, 0, 0, ?, ?)
                    """,
                arguments: [accountId, now, now]
            )
            let communityId = db.lastInsertedRowID
            return (accountId, siteId, communityId, personId)
        }
    }

    private func makeLemmy(pages: [RecordingLemmyService.Page]) -> RecordingLemmyService {
        RecordingLemmyService(
            appDatabase: appDatabase,
            accountId: accountId,
            communityId: communityId,
            personId: personId,
            pages: pages
        )
    }

    // MARK: - Tests

    @Test
    func download_emitsStartAndFinish() async throws {
        let spy = DiagnosticLogSpy()
        let lemmy = makeLemmy(pages: [.init(postCount: 3, nextCursor: nil)])
        let service = OfflineDownloadService(
            appDatabase: appDatabase,
            imageService: RecordingImageService(),
            diagnostics: spy
        )

        for await _ in service.download(
            feed: feed,
            lemmyService: lemmy,
            accountId: accountId,
            siteId: siteId,
            commentSort: commentSort,
            showNsfw: false,
            instance: "diag.instance"
        ) { }

        let startEvents = spy.events(matching: "download.start")
        #expect(startEvents.count == 1, "expected exactly one download.start event")
        let startEvent = try #require(startEvents.first)
        #expect(startEvent.category == .offlineDownload)
        #expect(startEvent.level == .info)
        #expect(startEvent.instance == "diag.instance")
        #expect(startEvent.metadata?["targetCount"] == "3")

        let finishEvents = spy.events(matching: "download.finish")
        #expect(finishEvents.count == 1, "expected exactly one download.finish event")
        let finishEvent = try #require(finishEvents.first)
        #expect(finishEvent.category == .offlineDownload)
        #expect(finishEvent.level == .info)
        #expect(finishEvent.instance == "diag.instance")
        #expect(finishEvent.metadata?["downloadedCount"] == "3")
        #expect(finishEvent.metadata?["failedCount"] == "0")
    }

    @Test
    func download_itemFailed_isRecorded_andFailedCountReflectsIt() async throws {
        let spy = DiagnosticLogSpy()
        // Posts are seeded with server ids starting at 1, so id 2 is the second post.
        let failingPostId: Int64 = 2
        let lemmy = RecordingLemmyService(
            appDatabase: appDatabase,
            accountId: accountId,
            communityId: communityId,
            personId: personId,
            pages: [.init(postCount: 3, nextCursor: nil)],
            failingCommentPostIds: [failingPostId]
        )
        let service = OfflineDownloadService(
            appDatabase: appDatabase,
            imageService: RecordingImageService(),
            diagnostics: spy
        )

        for await _ in service.download(
            feed: FeedHandle(feedKey: "diag-feed-fail", feedType: .frontpage(listingType: .All, sortType: .Hot)),
            lemmyService: lemmy,
            accountId: accountId,
            siteId: siteId,
            commentSort: commentSort,
            showNsfw: false,
            instance: "diag.instance"
        ) { }

        // One download.itemFailed event for the failing post.
        let itemFailedEvents = spy.events(matching: "download.itemFailed")
        #expect(itemFailedEvents.count == 1, "expected exactly one download.itemFailed event")
        let itemFailedEvent = try #require(itemFailedEvents.first)
        #expect(itemFailedEvent.category == .offlineDownload)
        #expect(itemFailedEvent.level == .notice)
        #expect(itemFailedEvent.instance == "diag.instance")
        #expect(itemFailedEvent.metadata?["serverPostId"] == String(failingPostId))

        // download.finish must reflect all 3 posts as downloaded (failed items
        // still count toward downloadedCount for the progress UI) and 1 failed
        // (for the diagnostic failedCount — a separate counter).
        let finishEvents = spy.events(matching: "download.finish")
        #expect(finishEvents.count == 1, "expected exactly one download.finish event")
        let finishEvent = try #require(finishEvents.first)
        #expect(finishEvent.metadata?["downloadedCount"] == "3")
        #expect(finishEvent.metadata?["failedCount"] == "1")
    }

    @Test
    func download_cancelled_emitsCancelledEvent() async throws {
        let spy = DiagnosticLogSpy()
        // Many pages with a non-nil cursor so the page loop runs long enough to
        // be cancelled before it completes.
        let manyPages = (0..<20).map { _ in
            RecordingLemmyService.Page(postCount: 1, nextCursor: "cursor")
        }
        let lemmy = RecordingLemmyService(
            appDatabase: appDatabase,
            accountId: accountId,
            communityId: communityId,
            personId: personId,
            pages: manyPages,
            exhaustedCursor: "cursor"
        )
        let service = OfflineDownloadService(
            appDatabase: appDatabase,
            imageService: RecordingImageService(),
            diagnostics: spy
        )

        // Await the first page-fetch call so the download is in-flight, then
        // cancel it. Consume the stream without cancelling it so the .cancelled
        // terminal is delivered.
        let downloadStream = service.download(
            feed: FeedHandle(feedKey: "diag-feed-cancel", feedType: .frontpage(listingType: .All, sortType: .Hot)),
            lemmyService: lemmy,
            accountId: accountId,
            siteId: siteId,
            commentSort: commentSort,
            showNsfw: false,
            instance: "diag.instance"
        )
        var iterator = downloadStream.makeAsyncIterator()

        // Read values until the first page arrives (service is actively running),
        // then cancel so the diagnostic event is recorded.
        await lemmy.firstFetchFeedStarted()
        await service.cancelCurrentDownload()

        // Drain the rest of the stream (delivers the .cancelled terminal).
        while let _ = await iterator.next() { }

        // At least one download.cancelled event must have been recorded.
        let cancelledEvents = spy.events(matching: "download.cancelled")
        #expect(!cancelledEvents.isEmpty, "expected at least one download.cancelled event")
        let cancelledEvent = try #require(cancelledEvents.first)
        #expect(cancelledEvent.category == .offlineDownload)
        #expect(cancelledEvent.level == .info)
        #expect(cancelledEvent.instance == "diag.instance")
    }
}
