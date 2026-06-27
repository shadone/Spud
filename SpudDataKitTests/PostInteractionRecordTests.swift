//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct PostInteractionRecordTests {
    @Test
    func convenienceInitDefaultsAreEmpty() {
        let record = PostInteractionRecord(accountId: 7, postServerId: 42)
        #expect(record.id == nil)
        #expect(record.accountId == 7)
        #expect(record.postServerId == 42)
        #expect(record.titleSnapshot == nil)
        #expect(record.firstSeenAt == nil)
        #expect(record.lastSeenAt == nil)
        #expect(record.seenCount == 0)
        #expect(record.lastOpenedAt == nil)
        #expect(record.openedCount == 0)
        #expect(record.lastKnownCommentCount == nil)
    }

    @Test
    func applySnapshotOverwritesSnapshotFields() {
        var record = PostInteractionRecord(accountId: 1, postServerId: 2)
        record.apply(PostInteractionSnapshot(
            titleSnapshot: "Hello",
            communityName: "tech",
            instanceHost: "lemmy.world",
            thumbnailUrl: "https://img.test/x.png",
            author: "alice"
        ))
        #expect(record.titleSnapshot == "Hello")
        #expect(record.communityName == "tech")
        #expect(record.instanceHost == "lemmy.world")
        #expect(record.thumbnailUrl == "https://img.test/x.png")
        #expect(record.author == "alice")
    }
}
