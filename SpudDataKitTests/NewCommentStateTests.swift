//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudDataKit

final class NewCommentStateTests: XCTestCase {
    /// Builds a comment row with the fields the delta reads. `more: true`
    /// produces a "load more" placeholder (no serverCommentId / published).
    private func row(
        id: Int64,
        position: Int64,
        publishedOffset: TimeInterval,
        creatorPersonId: Int64 = 1,
        more: Bool = false
    ) -> PostDetailCommentRow {
        PostDetailCommentRow(
            id: id,
            position: position,
            depth: 1,
            serverCommentId: more ? nil : id,
            body: more ? nil : "body \(id)",
            originalCommentUrl: more ? nil : "https://example.test/comment/\(id)",
            score: 0,
            voteStatus: nil,
            isSaved: more ? nil : false,
            isRemoved: more ? nil : false,
            isDistinguished: more ? nil : false,
            isDeleted: more ? nil : false,
            isCreatorModerator: more ? nil : false,
            isCreatorAdmin: more ? nil : false,
            isCreatorBannedFromCommunity: more ? nil : false,
            isCreatorBlocked: more ? nil : false,
            isCreatorSiteBanned: more ? nil : false,
            isCreatorBot: more ? nil : false,
            isCreatorAccountDeleted: more ? nil : false,
            removedReason: nil,
            published: more ? nil : Date(timeIntervalSince1970: 1_000_000 + publishedOffset),
            creatorName: more ? nil : "u\(id)",
            creatorPersonId: more ? nil : creatorPersonId,
            creatorInstanceActorId: more ? nil : "https://example.test",
            moreChildCount: more ? 3 : nil,
            moreParentId: more ? 1 : nil
        )
    }

    private let visit = Date(timeIntervalSince1970: 1_000_000 + 100)

    func testFirstVisitNilReferenceFlagsNothing() {
        let rows = [row(id: 1, position: 1, publishedOffset: 200)]
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: nil, currentAccountPersonId: nil)
        XCTAssertEqual(result.count, 0)
        XCTAssertNil(result.firstNewElementId)
    }

    func testCommentsAfterVisitAreNew() {
        let rows = [
            row(id: 1, position: 1, publishedOffset: 50), // before visit
            row(id: 2, position: 2, publishedOffset: 150), // after visit
            row(id: 3, position: 3, publishedOffset: 300), // after visit
        ]
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: visit, currentAccountPersonId: nil)
        XCTAssertEqual(result.newElementIds, [2, 3])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.firstNewElementId, 2)
    }

    func testOwnCommentsExcluded() {
        let rows = [
            row(id: 2, position: 2, publishedOffset: 150, creatorPersonId: 99), // mine
            row(id: 3, position: 3, publishedOffset: 300, creatorPersonId: 1),
        ]
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: visit, currentAccountPersonId: 99)
        XCTAssertEqual(result.newElementIds, [3])
        XCTAssertEqual(result.firstNewElementId, 3)
    }

    func testLoadMorePlaceholdersIgnored() {
        let rows = [
            row(id: 5, position: 5, publishedOffset: 0, more: true), // no published
            row(id: 6, position: 6, publishedOffset: 300),
        ]
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: visit, currentAccountPersonId: nil)
        XCTAssertEqual(result.newElementIds, [6])
    }

    func testFirstNewIsLowestPositionNotArrayOrder() {
        let rows = [
            row(id: 10, position: 9, publishedOffset: 300),
            row(id: 11, position: 4, publishedOffset: 300),
        ]
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: visit, currentAccountPersonId: nil)
        XCTAssertEqual(result.firstNewElementId, 11)
    }

    func testCommentExactlyAtVisitIsNotNew() {
        let rows = [row(id: 1, position: 1, publishedOffset: 100)] // published == visit
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: visit, currentAccountPersonId: nil)
        XCTAssertEqual(result.count, 0)
        XCTAssertFalse(result.newElementIds.contains(1))
    }

    func testEmptyInputReturnsEmptyResult() {
        let result = NewCommentState.compute(orderedComments: [], previousVisitAt: visit, currentAccountPersonId: nil)
        XCTAssertEqual(result.count, 0)
        XCTAssertNil(result.firstNewElementId)
    }
}
