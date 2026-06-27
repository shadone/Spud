//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct NewCommentStateTests {
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
            creatorActorId: more ? nil : "https://example.test",
            moreChildCount: more ? 3 : nil,
            moreParentId: more ? 1 : nil
        )
    }

    private let visit = Date(timeIntervalSince1970: 1_000_000 + 100)

    @Test
    func firstVisitNilReferenceFlagsNothing() {
        let rows = [row(id: 1, position: 1, publishedOffset: 200)]
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: nil, currentAccountPersonId: nil)
        // swiftformat:disable:next isEmpty
        #expect(result.count == 0)
        #expect(result.firstNewElementId == nil)
    }

    @Test
    func commentsAfterVisitAreNew() {
        let rows = [
            row(id: 1, position: 1, publishedOffset: 50), // before visit
            row(id: 2, position: 2, publishedOffset: 150), // after visit
            row(id: 3, position: 3, publishedOffset: 300), // after visit
        ]
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: visit, currentAccountPersonId: nil)
        #expect(result.newElementIds == [2, 3])
        #expect(result.count == 2)
        #expect(result.firstNewElementId == 2)
    }

    @Test
    func ownCommentsExcluded() {
        let rows = [
            row(id: 2, position: 2, publishedOffset: 150, creatorPersonId: 99), // mine
            row(id: 3, position: 3, publishedOffset: 300, creatorPersonId: 1),
        ]
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: visit, currentAccountPersonId: 99)
        #expect(result.newElementIds == [3])
        #expect(result.firstNewElementId == 3)
    }

    @Test
    func loadMorePlaceholdersIgnored() {
        let rows = [
            row(id: 5, position: 5, publishedOffset: 0, more: true), // no published
            row(id: 6, position: 6, publishedOffset: 300),
        ]
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: visit, currentAccountPersonId: nil)
        #expect(result.newElementIds == [6])
    }

    @Test
    func firstNewIsLowestPositionNotArrayOrder() {
        let rows = [
            row(id: 10, position: 9, publishedOffset: 300),
            row(id: 11, position: 4, publishedOffset: 300),
        ]
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: visit, currentAccountPersonId: nil)
        #expect(result.firstNewElementId == 11)
    }

    @Test
    func commentExactlyAtVisitIsNotNew() {
        let rows = [row(id: 1, position: 1, publishedOffset: 100)] // published == visit
        let result = NewCommentState.compute(orderedComments: rows, previousVisitAt: visit, currentAccountPersonId: nil)
        // swiftformat:disable:next isEmpty
        #expect(result.count == 0)
        #expect(!(result.newElementIds.contains(1)))
    }

    @Test
    func emptyInputReturnsEmptyResult() {
        let result = NewCommentState.compute(orderedComments: [], previousVisitAt: visit, currentAccountPersonId: nil)
        // swiftformat:disable:next isEmpty
        #expect(result.count == 0)
        #expect(result.firstNewElementId == nil)
    }
}
