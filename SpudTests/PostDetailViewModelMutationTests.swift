//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import Testing
@testable import Spud

/// Unit tests for `PostDetailViewModel`'s thin dispatch methods — the ones that
/// forward a PostDetail action to the account's `LemmyService` through the
/// `PostDetailLemmyServicing` seam. Each method is asserted to forward the exact
/// server ids / arguments (via the recording double) and to rethrow service
/// errors unchanged. Grows one call-site group at a time alongside the seam.
@MainActor
struct PostDetailViewModelMutationTests {
    private struct TestDependencies:
        HasAccountService, HasAlertService, HasPreferencesService, HasReachabilityMonitor
    {
        let appDatabase: AppDatabase
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let preferencesService: PreferencesServiceType
        let reachabilityMonitor: ReachabilityMonitoring

        init() {
            let appDatabase = try! AppDatabase.inMemory()
            self.appDatabase = appDatabase
            accountService = AccountService(appDatabase: appDatabase)
            alertService = AlertService()
            preferencesService = PreferencesService.ephemeral()
            reachabilityMonitor = StaticReachabilityMonitor(isOnline: true)
        }
    }

    /// Builds a view model wired to the injected `lemmy` double. `serverPostId`
    /// is fixed at 1 so the report-post forwarding test can assert the VM
    /// supplies its own post id. `fetchCommentsOperation` is accepted for the
    /// refresh-path tests later groups add (unused by the report group).
    private func makeViewModel(
        lemmy: any PostDetailLemmyServicing,
        fetchCommentsOperation: (@MainActor (Components.Schemas.CommentSortType) async throws -> Void)? = nil
    ) -> PostDetailViewModel {
        let dependencies = TestDependencies()
        return PostDetailViewModel(
            serverPostId: 1,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: "kc-1"),
            appDatabase: dependencies.appDatabase,
            dependencies: dependencies,
            lemmy: lemmy,
            fetchCommentsOperation: fetchCommentsOperation
        )
    }

    // MARK: - Report

    @Test
    func reportPostForwardsOwnPostIdAndReason() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.reportPost(reason: "spam")

        #expect(recording.invocations == [.reportPost(serverPostId: 1, reason: "spam")])
    }

    @Test
    func reportPostRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            try await vm.reportPost(reason: "spam")
        }
        #expect(recording.invocations.isEmpty)
    }

    @Test
    func reportCommentForwardsCommentIdAndReason() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.reportComment(serverCommentId: 42, reason: "abuse")

        #expect(recording.invocations == [.reportComment(serverCommentId: 42, reason: "abuse")])
    }

    @Test
    func reportCommentRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            try await vm.reportComment(serverCommentId: 42, reason: "abuse")
        }
        #expect(recording.invocations.isEmpty)
    }

    // MARK: - Delete / Restore

    @Test
    func deleteCommentForwardsCommentIdAndDeletedFlag() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.deleteComment(serverCommentId: 42, deleted: true)

        #expect(recording.invocations == [.deleteComment(serverCommentId: 42, deleted: true)])
    }

    @Test
    func deleteCommentRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            try await vm.deleteComment(serverCommentId: 42, deleted: true)
        }
        #expect(recording.invocations.isEmpty)
    }

    @Test
    func deletePostForwardsPostIdAndDeletedFlag() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.deletePost(serverPostId: 1, deleted: true)

        #expect(recording.invocations == [.deletePost(serverPostId: 1, deleted: true)])
    }

    @Test
    func deletePostForwardsRestoreFlavor() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.deletePost(serverPostId: 1, deleted: false)

        #expect(recording.invocations == [.deletePost(serverPostId: 1, deleted: false)])
    }

    @Test
    func deletePostRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            try await vm.deletePost(serverPostId: 1, deleted: true)
        }
        #expect(recording.invocations.isEmpty)
    }

    // MARK: - Moderation

    @Test
    func removePostForwardsPostIdRemovedFlagAndReason() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.removePost(serverPostId: 1, removed: true, reason: "spam")

        #expect(recording.invocations == [.removePost(serverPostId: 1, removed: true, reason: "spam")])
    }

    @Test
    func removePostForwardsNilReason() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.removePost(serverPostId: 1, removed: false, reason: nil)

        #expect(recording.invocations == [.removePost(serverPostId: 1, removed: false, reason: nil)])
    }

    @Test
    func removePostRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            try await vm.removePost(serverPostId: 1, removed: true, reason: nil)
        }
        #expect(recording.invocations.isEmpty)
    }

    @Test
    func lockPostForwardsPostIdAndLockedFlag() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.lockPost(serverPostId: 1, locked: true)

        #expect(recording.invocations == [.lockPost(serverPostId: 1, locked: true)])
    }

    @Test
    func lockPostRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            try await vm.lockPost(serverPostId: 1, locked: true)
        }
        #expect(recording.invocations.isEmpty)
    }

    @Test
    func featurePostForwardsPostIdFeaturedAndLocalFlags() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.featurePost(serverPostId: 1, featured: true, local: false)

        #expect(recording.invocations == [.featurePost(serverPostId: 1, featured: true, local: false)])
    }

    @Test
    func featurePostRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            try await vm.featurePost(serverPostId: 1, featured: true, local: true)
        }
        #expect(recording.invocations.isEmpty)
    }

    @Test
    func removeCommentForwardsCommentIdRemovedFlagAndReason() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.removeComment(serverCommentId: 42, removed: true, reason: "abuse")

        #expect(recording.invocations == [.removeComment(serverCommentId: 42, removed: true, reason: "abuse")])
    }

    @Test
    func removeCommentForwardsNilReason() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.removeComment(serverCommentId: 42, removed: false, reason: nil)

        #expect(recording.invocations == [.removeComment(serverCommentId: 42, removed: false, reason: nil)])
    }

    @Test
    func removeCommentRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            try await vm.removeComment(serverCommentId: 42, removed: true, reason: nil)
        }
        #expect(recording.invocations.isEmpty)
    }

    @Test
    func distinguishCommentForwardsCommentIdAndDistinguishedFlag() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.distinguishComment(serverCommentId: 42, distinguished: true)

        #expect(recording.invocations == [.distinguishComment(serverCommentId: 42, distinguished: true)])
    }

    @Test
    func distinguishCommentRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            try await vm.distinguishComment(serverCommentId: 42, distinguished: true)
        }
        #expect(recording.invocations.isEmpty)
    }

    @Test
    func banFromCommunityForwardsIdsAndBakesBanTrue() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.banFromCommunity(
            communityId: 7,
            serverPersonId: 42,
            removeData: true,
            reason: "spam"
        )

        #expect(recording.invocations == [
            .banFromCommunity(
                serverCommunityId: 7,
                serverPersonId: 42,
                ban: true,
                removeData: true,
                reason: "spam"
            ),
        ])
    }

    @Test
    func banFromCommunityForwardsNilReason() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.banFromCommunity(
            communityId: 7,
            serverPersonId: 42,
            removeData: false,
            reason: nil
        )

        #expect(recording.invocations == [
            .banFromCommunity(
                serverCommunityId: 7,
                serverPersonId: 42,
                ban: true,
                removeData: false,
                reason: nil
            ),
        ])
    }

    @Test
    func banFromCommunityRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            try await vm.banFromCommunity(
                communityId: 7,
                serverPersonId: 42,
                removeData: true,
                reason: nil
            )
        }
        #expect(recording.invocations.isEmpty)
    }

    // MARK: - Pending comments (retry / discard) + block

    @Test
    func retryCompositionForwardsClientToken() async {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        await vm.retryComposition(clientToken: "token-1")

        #expect(recording.invocations == [.retryComposition(clientToken: "token-1")])
    }

    @Test
    func discardCompositionForwardsClientToken() async {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        await vm.discardComposition(clientToken: "token-1")

        #expect(recording.invocations == [.discardComposition(clientToken: "token-1")])
    }

    @Test
    func blockAuthorForwardsPersonIdAndBakesBlockedTrue() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.blockAuthor(serverPersonId: 42)

        #expect(recording.invocations == [.setBlocked(serverPersonId: 42, blocked: true)])
    }

    @Test
    func blockAuthorRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            try await vm.blockAuthor(serverPersonId: 42)
        }
        #expect(recording.invocations.isEmpty)
    }

    // MARK: - Read-path wrappers (mark-as-read / post info / mod capability)

    @Test
    func markAsReadForwardsOwnPostId() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.markAsRead()

        #expect(recording.invocations == [.markAsRead(serverPostId: 1)])
    }

    @Test
    func markAsReadRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            try await vm.markAsRead()
        }
        #expect(recording.invocations.isEmpty)
    }

    @Test
    func refreshPostInfoForwardsOwnPostId() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.refreshPostInfo()

        #expect(recording.invocations == [.fetchPostInfo(serverPostId: 1)])
    }

    @Test
    func refreshPostInfoRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            try await vm.refreshPostInfo()
        }
        #expect(recording.invocations.isEmpty)
    }

    @Test
    func fetchModerationCapabilityForwardsAndReturnsCapability() async throws {
        let recording = RecordingPostDetailLemmyService()
        let expected = ModerationCapability(moderatedCommunityIds: [7], isAdmin: true)
        recording.moderationCapabilityToReturn = expected
        let vm = makeViewModel(lemmy: recording)

        let capability = try await vm.fetchModerationCapability()

        #expect(capability == expected)
        #expect(recording.invocations == [.fetchModerationCapability])
    }

    @Test
    func fetchModerationCapabilityRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            _ = try await vm.fetchModerationCapability()
        }
        #expect(recording.invocations.isEmpty)
    }

    // MARK: - Refresh comments (reuses the fetch closure seam, not the protocol)

    @Test
    func refreshCommentsCallsFetchClosureWithCurrentSortType() async throws {
        let recording = RecordingPostDetailLemmyService()
        let spy = CommentSortTypeSpy()
        let vm = makeViewModel(
            lemmy: recording,
            fetchCommentsOperation: { sortType in spy.record(sortType) }
        )
        vm.setCommentSortType(.New)

        try await vm.refreshComments()

        // Routes through the existing `fetchCommentsOperation` closure with the
        // view model's current sort type — never through the protocol seam.
        #expect(spy.received == [.New])
        #expect(recording.invocations.isEmpty)
        // The bare closure call must not enter the `fetchComments()`
        // cancel-and-replace state machine.
        #expect(vm.isLoadingComments == false)
        #expect(vm.commentFetchError == nil)
    }

    @Test
    func refreshCommentsRethrowsFetchError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(
            lemmy: recording,
            fetchCommentsOperation: { _ in throw Boom() }
        )

        await #expect(throws: Boom.self) {
            try await vm.refreshComments()
        }
    }

    // MARK: - Comment vote / save

    @Test
    func voteOnCommentForwardsCommentIdAndAction() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.voteOnComment(serverCommentId: 42, action: .upvote)

        #expect(recording.invocations == [.vote(serverCommentId: 42, action: .upvote)])
    }

    @Test
    func voteOnCommentForwardsDownvoteAction() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.voteOnComment(serverCommentId: 42, action: .downvote)

        #expect(recording.invocations == [.vote(serverCommentId: 42, action: .downvote)])
    }

    @Test
    func voteOnCommentRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            try await vm.voteOnComment(serverCommentId: 42, action: .upvote)
        }
        #expect(recording.invocations.isEmpty)
    }

    @Test
    func setSavedOnCommentForwardsCommentIdAndSavedFlag() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.setSavedOnComment(serverCommentId: 42, saved: true)

        #expect(recording.invocations == [.setSaved(serverCommentId: 42, saved: true)])
    }

    @Test
    func setSavedOnCommentForwardsUnsaveFlavor() async throws {
        let recording = RecordingPostDetailLemmyService()
        let vm = makeViewModel(lemmy: recording)

        try await vm.setSavedOnComment(serverCommentId: 42, saved: false)

        #expect(recording.invocations == [.setSaved(serverCommentId: 42, saved: false)])
    }

    @Test
    func setSavedOnCommentRethrowsServiceError() async {
        struct Boom: Error { }
        let recording = RecordingPostDetailLemmyService()
        recording.errorToThrow = Boom()
        let vm = makeViewModel(lemmy: recording)

        await #expect(throws: Boom.self) {
            try await vm.setSavedOnComment(serverCommentId: 42, saved: true)
        }
        #expect(recording.invocations.isEmpty)
    }
}

/// Captures the sort types the injected `fetchCommentsOperation` closure
/// receives, so `refreshCommentsCallsFetchClosureWithCurrentSortType` can assert
/// the refresh routes the view model's current `commentSortType` through the
/// existing closure seam. `@MainActor` to match the closure's isolation.
@MainActor
private final class CommentSortTypeSpy {
    private(set) var received: [Components.Schemas.CommentSortType] = []

    func record(_ sortType: Components.Schemas.CommentSortType) {
        received.append(sortType)
    }
}
