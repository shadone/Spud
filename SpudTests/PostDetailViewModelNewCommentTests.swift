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
        preferencesService = PreferencesService()
        reachabilityMonitor = StaticReachabilityMonitor(isOnline: true)
    }
}

@MainActor
struct PostDetailViewModelNewCommentTests {
    private func makeRow(id: Int64, publishedOffset: TimeInterval, creatorPersonId: Int64 = 1) -> PostDetailCommentRow {
        PostDetailCommentRow(
            id: id, position: id, depth: 1,
            serverCommentId: id, body: "b\(id)",
            originalCommentUrl: "https://example.test/comment/\(id)",
            score: 0, voteStatus: nil, isSaved: false, isRemoved: false,
            isDistinguished: false, isDeleted: false, isCreatorModerator: false,
            isCreatorAdmin: false, isCreatorBannedFromCommunity: false,
            isCreatorBlocked: false, isCreatorSiteBanned: false, isCreatorBot: false,
            isCreatorAccountDeleted: false, removedReason: nil,
            published: Date(timeIntervalSince1970: 1_000_000 + publishedOffset),
            creatorName: "u\(id)", creatorPersonId: creatorPersonId,
            creatorActorId: "https://example.test",
            moreChildCount: nil, moreParentId: nil
        )
    }

    private func makeViewModel() -> PostDetailViewModel {
        let dependencies = TestDependencies()
        return PostDetailViewModel(
            serverPostId: 1,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: "kc-1"),
            appDatabase: dependencies.appDatabase,
            dependencies: dependencies
        )
    }

    @Test
    func noPriorVisitFlagsNothing() {
        let vm = makeViewModel()
        vm.previousVisitAt = nil
        vm.updateOrderedComments([makeRow(id: 1, publishedOffset: 500)])
        #expect(vm.newCommentCount == 0)
        #expect(!vm.isNewComment(elementId: 1))
        #expect(vm.firstNewCommentElementId == nil)
    }

    @Test
    func flagsCommentsAfterPriorVisit() {
        let vm = makeViewModel()
        vm.previousVisitAt = Date(timeIntervalSince1970: 1_000_000 + 100)
        vm.currentAccountPersonId = nil
        vm.updateOrderedComments([
            makeRow(id: 1, publishedOffset: 50),
            makeRow(id: 2, publishedOffset: 300),
        ])
        #expect(vm.newCommentCount == 1)
        #expect(vm.isNewComment(elementId: 2))
        #expect(!vm.isNewComment(elementId: 1))
        #expect(vm.firstNewCommentElementId == 2)
    }

    @Test
    func ownCommentExcluded() {
        let vm = makeViewModel()
        vm.previousVisitAt = Date(timeIntervalSince1970: 1_000_000 + 100)
        vm.currentAccountPersonId = 99
        vm.updateOrderedComments([makeRow(id: 5, publishedOffset: 300, creatorPersonId: 99)])
        #expect(vm.newCommentCount == 0)
    }

    @Test
    func orderedNewCommentElementIdsAreInDisplayOrderAndOnlyNew() {
        let vm = makeViewModel()
        vm.previousVisitAt = Date(timeIntervalSince1970: 1_000_000 + 100)
        vm.currentAccountPersonId = nil
        vm.updateOrderedComments([
            makeRow(id: 10, publishedOffset: 50), // before visit -> not new
            makeRow(id: 11, publishedOffset: 200), // new
            makeRow(id: 12, publishedOffset: 300), // new
        ])
        #expect(vm.orderedNewCommentElementIds == [11, 12])
    }

    @Test
    func orderedNewCommentElementIdsEmptyOnFirstVisit() {
        let vm = makeViewModel()
        vm.previousVisitAt = nil
        vm.updateOrderedComments([makeRow(id: 1, publishedOffset: 500)])
        #expect(vm.orderedNewCommentElementIds == [])
    }
}
