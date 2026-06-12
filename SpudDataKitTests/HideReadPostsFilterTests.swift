//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudDataKit

final class HideReadPostsFilterTests: XCTestCase {
    /// Builds a PostListRow with only the fields the hide-read filter reads:
    /// `serverPostId` and `isRead`. Everything else is filler.
    private func row(serverPostId: Int64, isRead: Bool) -> PostListRow {
        PostListRow(
            id: serverPostId,
            serverPostId: serverPostId,
            title: "post \(serverPostId)",
            body: nil,
            originalPostUrl: "https://example.test/post/\(serverPostId)",
            url: nil,
            thumbnailUrl: nil,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            communityName: "c",
            communityActorId: nil,
            serverCommunityId: 1,
            creatorPersonId: 1,
            score: 0,
            numberOfComments: 0,
            voteStatus: nil,
            isRead: isRead,
            isSaved: false,
            isRemoved: false,
            isLocked: false,
            isFeaturedCommunity: false,
            isFeaturedLocal: false,
            isDeleted: false,
            published: Date(timeIntervalSince1970: 0)
        )
    }

    /// Feed of three posts: #1 read, #2 unread, #3 read.
    private func sampleFeed() -> [PostListRow] {
        [
            row(serverPostId: 1, isRead: true),
            row(serverPostId: 2, isRead: false),
            row(serverPostId: 3, isRead: true),
        ]
    }

    func testDisabledReturnsAllRowsUnchanged() {
        let rows = sampleFeed()
        let result = HideReadPostsFilter.filter(
            rows: rows,
            enabled: false,
            mode: .live
        )
        XCTAssertEqual(result.map(\.serverPostId), [1, 2, 3])
    }

    func testLiveModeDropsEveryReadRow() {
        let rows = sampleFeed()
        let result = HideReadPostsFilter.filter(
            rows: rows,
            enabled: true,
            mode: .live
        )
        XCTAssertEqual(result.map(\.serverPostId), [2])
    }

    func testLiveModePreservesOrderOfRemainingRows() {
        let rows = [
            row(serverPostId: 10, isRead: false),
            row(serverPostId: 11, isRead: true),
            row(serverPostId: 12, isRead: false),
            row(serverPostId: 13, isRead: false),
        ]
        let result = HideReadPostsFilter.filter(
            rows: rows,
            enabled: true,
            mode: .live
        )
        XCTAssertEqual(result.map(\.serverPostId), [10, 12, 13])
    }

    func testOnRefreshHidesOnlyPinnedReadRows() {
        // #1 and #3 are read; only #1 was read at refresh time. #3 became read
        // during the session and should remain visible until the next refresh.
        let rows = sampleFeed()
        let result = HideReadPostsFilter.filter(
            rows: rows,
            enabled: true,
            mode: .onRefresh,
            pinnedReadIds: [1]
        )
        XCTAssertEqual(result.map(\.serverPostId), [2, 3])
    }

    func testOnRefreshWithNoPinnedReadIdsHidesNothing() {
        let rows = sampleFeed()
        let result = HideReadPostsFilter.filter(
            rows: rows,
            enabled: true,
            mode: .onRefresh,
            pinnedReadIds: []
        )
        XCTAssertEqual(result.map(\.serverPostId), [1, 2, 3])
    }

    func testOnRefreshPinnedButNowUnreadRowStaysVisible() {
        // A row pinned as read that has since been marked unread (e.g. via the
        // server) is not hidden — the filter checks the row's current isRead.
        let rows = [
            row(serverPostId: 1, isRead: false),
            row(serverPostId: 2, isRead: true),
        ]
        let result = HideReadPostsFilter.filter(
            rows: rows,
            enabled: true,
            mode: .onRefresh,
            pinnedReadIds: [1, 2]
        )
        XCTAssertEqual(result.map(\.serverPostId), [1])
    }

    func testReadIdsCollectsReadServerPostIds() {
        let ids = HideReadPostsFilter.readIds(in: sampleFeed())
        XCTAssertEqual(ids, [1, 3])
    }

    func testReadIdsEmptyWhenNothingRead() {
        let rows = [
            row(serverPostId: 1, isRead: false),
            row(serverPostId: 2, isRead: false),
        ]
        XCTAssertTrue(HideReadPostsFilter.readIds(in: rows).isEmpty)
    }
}
