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
final class PostDetailViewModelNewCommentTests: XCTestCase {
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
            creatorInstanceActorId: "https://example.test",
            moreChildCount: nil, moreParentId: nil
        )
    }

    private func makeViewModel() -> PostDetailViewModel {
        PostDetailViewModel(
            serverPostId: 1,
            accountKeychainId: "kc-1",
            dependencies: TestDependencies()
        )
    }

    func testNoPriorVisitFlagsNothing() {
        let vm = makeViewModel()
        vm.previousVisitAt = nil
        vm.updateOrderedComments([makeRow(id: 1, publishedOffset: 500)])
        XCTAssertEqual(vm.newCommentCount, 0)
        XCTAssertFalse(vm.isNewComment(elementId: 1))
        XCTAssertNil(vm.firstNewCommentElementId)
    }

    func testFlagsCommentsAfterPriorVisit() {
        let vm = makeViewModel()
        vm.previousVisitAt = Date(timeIntervalSince1970: 1_000_000 + 100)
        vm.currentAccountPersonId = nil
        vm.updateOrderedComments([
            makeRow(id: 1, publishedOffset: 50),
            makeRow(id: 2, publishedOffset: 300),
        ])
        XCTAssertEqual(vm.newCommentCount, 1)
        XCTAssertTrue(vm.isNewComment(elementId: 2))
        XCTAssertFalse(vm.isNewComment(elementId: 1))
        XCTAssertEqual(vm.firstNewCommentElementId, 2)
    }

    func testOwnCommentExcluded() {
        let vm = makeViewModel()
        vm.previousVisitAt = Date(timeIntervalSince1970: 1_000_000 + 100)
        vm.currentAccountPersonId = 99
        vm.updateOrderedComments([makeRow(id: 5, publishedOffset: 300, creatorPersonId: 99)])
        XCTAssertEqual(vm.newCommentCount, 0)
    }
}
