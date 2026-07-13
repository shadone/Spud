//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
@testable import Spud

/// Covers `RemindMeMenuTarget`'s `rootCommentServerId` default (Phase 3) -
/// every existing whole-post caller (post detail overflow menu, feed cell
/// long-press) constructs a target without passing `rootCommentServerId`, so
/// this default must stay `ReminderRecord.wholePostSentinel` or every
/// whole-post reminder would silently start behaving like a subtree one.
struct RemindMeMenuTargetTests {
    @Test
    func defaultRootCommentServerIdIsWholePostSentinel() {
        let target = RemindMeMenuTarget(
            postServerId: 42,
            apId: "https://lemmy.world/post/42",
            title: "A scenic mountain lake at golden hour",
            communityName: "photography",
            instanceHost: "lemmy.world",
            thumbnailUrl: nil,
            numberOfComments: 12
        )
        #expect(target.rootCommentServerId == ReminderRecord.wholePostSentinel)
    }

    @Test
    func explicitRootCommentServerIdScopesToTheComment() {
        let target = RemindMeMenuTarget(
            postServerId: 42,
            apId: "https://lemmy.world/comment/99",
            title: "A scenic mountain lake at golden hour",
            communityName: "photography",
            instanceHost: "lemmy.world",
            thumbnailUrl: nil,
            numberOfComments: 3,
            rootCommentServerId: 99
        )
        #expect(target.rootCommentServerId == 99)
        #expect(target.apId == "https://lemmy.world/comment/99")
    }
}
