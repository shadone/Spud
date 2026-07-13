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
struct PostDetailViewModelExpandAncestorsTests {
    private func row(id: Int64, depth: Int64, publishedOffset: TimeInterval = 0) -> PostDetailCommentRow {
        PostDetailCommentRow(
            id: id, position: id, depth: depth,
            serverCommentId: id, body: "b\(id)",
            originalCommentUrl: "https://example.test/comment/\(id)",
            score: 0, voteStatus: nil, isSaved: false, isRemoved: false,
            isDistinguished: false, isDeleted: false, isCreatorModerator: false,
            isCreatorAdmin: false, isCreatorBannedFromCommunity: false,
            isCreatorBlocked: false, isCreatorSiteBanned: false, isCreatorBot: false,
            isCreatorAccountDeleted: false, removedReason: nil,
            published: Date(timeIntervalSince1970: 1_000_000 + publishedOffset),
            creatorName: "u\(id)", creatorPersonId: id,
            creatorActorId: "https://example.test",
            moreChildCount: nil, moreParentId: nil, childCount: nil
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
    func expandAncestorsRevealsCollapsedParent() {
        let vm = makeViewModel()
        vm.updateOrderedComments([row(id: 1, depth: 1), row(id: 2, depth: 2), row(id: 3, depth: 3)])
        vm.toggleCollapse(elementId: 1)
        #expect(vm.isCollapsed(elementId: 1))

        #expect(vm.expandAncestors(toReveal: 3))
        #expect(!vm.isCollapsed(elementId: 1))
    }

    @Test
    func expandAncestorsRemovesNestedCollapsedAncestors() {
        let vm = makeViewModel()
        vm.updateOrderedComments([row(id: 1, depth: 1), row(id: 2, depth: 2), row(id: 3, depth: 3)])
        vm.toggleCollapse(elementId: 1)
        vm.toggleCollapse(elementId: 2)

        #expect(vm.expandAncestors(toReveal: 3))
        #expect(!vm.isCollapsed(elementId: 1))
        #expect(!vm.isCollapsed(elementId: 2))
    }

    @Test
    func expandAncestorsIsIdempotentWhenAlreadyVisible() {
        let vm = makeViewModel()
        vm.updateOrderedComments([row(id: 1, depth: 1), row(id: 2, depth: 2)])
        #expect(!vm.expandAncestors(toReveal: 2))
    }

    @Test
    func visibleCommentTreeSurfacesCollapsedNewCounts() {
        let vm = makeViewModel()
        vm.previousVisitAt = Date(timeIntervalSince1970: 1_000_000 + 100)
        vm.currentAccountPersonId = nil
        // 1 > (2 old, 3 new). Collapse 1.
        vm.updateOrderedComments([
            row(id: 1, depth: 1, publishedOffset: 50),
            row(id: 2, depth: 2, publishedOffset: 50),
            row(id: 3, depth: 2, publishedOffset: 300),
        ])
        vm.toggleCollapse(elementId: 1)

        let tree = vm.visibleCommentTree()
        #expect(tree.collapsedDescendantCounts[1] == 2)
        #expect(tree.collapsedNewDescendantCounts[1] == 1)
    }
}
