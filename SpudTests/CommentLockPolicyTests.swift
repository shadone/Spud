//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

struct CommentLockPolicyTests {
    @Test
    func lockedPostCannotBeCommented() {
        #expect(CommentLockPolicy.canComment(isPostLocked: true) == false)
    }

    @Test
    func unlockedPostCanBeCommented() {
        #expect(CommentLockPolicy.canComment(isPostLocked: false) == true)
    }

    @Test
    func copyIsNonEmptyAndDistinct() {
        #expect(!CommentLockPolicy.title.isEmpty)
        #expect(!CommentLockPolicy.message.isEmpty)
        #expect(!CommentLockPolicy.shortStatus.isEmpty)
        #expect(CommentLockPolicy.title != CommentLockPolicy.message)
    }
}
