//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct PostInteractionSnapshotMappingTests {
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

    @Test
    func mapsFieldsAndDerivesInstanceHost() {
        let snap = PostInteractionSnapshot(postListRow: row(communityActorId: "https://lemmy.world/c/programming"))
        #expect(snap.titleSnapshot == "Hello")
        #expect(snap.communityName == "programming")
        #expect(snap.instanceHost == "lemmy.world")
        #expect(snap.thumbnailUrl == "https://img.test/t.png")
        #expect(snap.author == "alice")
    }

    @Test
    func instanceHostEmptyWhenActorIdMissing() {
        let snap = PostInteractionSnapshot(postListRow: row(communityActorId: nil))
        #expect(snap.instanceHost == "")
    }
}
