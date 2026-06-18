//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import XCTest
@testable import Spud

private struct TestDependencies:
    HasAccountService, HasAlertService, HasPreferencesService
{
    let accountService: AccountServiceType
    let alertService: AlertServiceType
    let preferencesService: PreferencesServiceType

    init() {
        let appDatabase = try! AppDatabase.inMemory()
        accountService = AccountService(appDatabase: appDatabase)
        alertService = AlertService()
        preferencesService = PreferencesService()
    }
}

@MainActor
final class PostDetailViewModelExpandAncestorsTests: XCTestCase {
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
            creatorInstanceActorId: "https://example.test",
            moreChildCount: nil, moreParentId: nil
        )
    }

    private func makeViewModel() -> PostDetailViewModel {
        let dependencies = TestDependencies()
        return PostDetailViewModel(
            serverPostId: 1,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: "kc-1"),
            dependencies: dependencies
        )
    }

    func testExpandAncestorsRevealsCollapsedParent() {
        let vm = makeViewModel()
        vm.updateOrderedComments([row(id: 1, depth: 1), row(id: 2, depth: 2), row(id: 3, depth: 3)])
        vm.toggleCollapse(elementId: 1)
        XCTAssertTrue(vm.isCollapsed(elementId: 1))

        XCTAssertTrue(vm.expandAncestors(toReveal: 3))
        XCTAssertFalse(vm.isCollapsed(elementId: 1))
    }

    func testExpandAncestorsRemovesNestedCollapsedAncestors() {
        let vm = makeViewModel()
        vm.updateOrderedComments([row(id: 1, depth: 1), row(id: 2, depth: 2), row(id: 3, depth: 3)])
        vm.toggleCollapse(elementId: 1)
        vm.toggleCollapse(elementId: 2)

        XCTAssertTrue(vm.expandAncestors(toReveal: 3))
        XCTAssertFalse(vm.isCollapsed(elementId: 1))
        XCTAssertFalse(vm.isCollapsed(elementId: 2))
    }

    func testExpandAncestorsIsIdempotentWhenAlreadyVisible() {
        let vm = makeViewModel()
        vm.updateOrderedComments([row(id: 1, depth: 1), row(id: 2, depth: 2)])
        XCTAssertFalse(vm.expandAncestors(toReveal: 2))
    }

    func testVisibleCommentTreeSurfacesCollapsedNewCounts() {
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
        XCTAssertEqual(tree.collapsedDescendantCounts[1], 2)
        XCTAssertEqual(tree.collapsedNewDescendantCounts[1], 1)
    }
}
