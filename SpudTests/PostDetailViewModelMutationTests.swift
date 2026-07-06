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
}
