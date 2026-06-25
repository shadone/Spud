//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudDataKit

final class PostInteractionSnapshotMappingTests: XCTestCase {
    private func row(communityActorId: String?) -> PostListRow {
        PostListRow(
            id: 1, serverPostId: 9, title: "Hello", body: nil,
            originalPostUrl: "https://lemmy.world/post/9", url: nil, thumbnailUrl: "https://img.test/t.png",
            urlEmbedTitle: nil, urlEmbedDescription: nil, altText: nil,
            communityName: "programming", communityActorId: communityActorId, serverCommunityId: 5,
            creatorPersonId: 10, creatorName: "alice", creatorActorId: "https://lemmy.world/u/alice",
            score: 7, numberOfComments: 3, voteStatus: nil, isRead: false, isSaved: false,
            isRemoved: false, isLocked: false, isFeaturedCommunity: false, isFeaturedLocal: false,
            isDeleted: false, isNsfw: false, published: Date(timeIntervalSince1970: 0)
        )
    }

    func testMapsFieldsAndDerivesInstanceHost() {
        let snap = PostInteractionSnapshot(postListRow: row(communityActorId: "https://lemmy.world/c/programming"))
        XCTAssertEqual(snap.titleSnapshot, "Hello")
        XCTAssertEqual(snap.communityName, "programming")
        XCTAssertEqual(snap.instanceHost, "lemmy.world")
        XCTAssertEqual(snap.thumbnailUrl, "https://img.test/t.png")
        XCTAssertEqual(snap.author, "alice")
    }

    func testInstanceHostEmptyWhenActorIdMissing() {
        let snap = PostInteractionSnapshot(postListRow: row(communityActorId: nil))
        XCTAssertEqual(snap.instanceHost, "")
    }
}
