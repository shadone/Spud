//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
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

    // MARK: - sanitizedSwipeActionConfig

    @Test
    func sanitizedSwipeActionConfigClearsReplySlotWhenLocked() {
        let config = SwipeActionConfig(
            leadingPrimary: .upvote,
            leadingSecondary: .downvote,
            trailingPrimary: .reply,
            trailingSecondary: .collapse
        )
        let sanitized = CommentLockPolicy.sanitizedSwipeActionConfig(config, isPostLocked: true)
        #expect(sanitized.trailingPrimary == .none)
        // Every other slot is untouched.
        #expect(sanitized.leadingPrimary == .upvote)
        #expect(sanitized.leadingSecondary == .downvote)
        #expect(sanitized.trailingSecondary == .collapse)
    }

    @Test
    func sanitizedSwipeActionConfigClearsReplyRegardlessOfSlot() {
        // Reply reassigned to a different slot (user customization) is still
        // cleared wherever it lives.
        let config = SwipeActionConfig(
            leadingPrimary: .reply,
            leadingSecondary: .save,
            trailingPrimary: .upvote,
            trailingSecondary: .downvote
        )
        let sanitized = CommentLockPolicy.sanitizedSwipeActionConfig(config, isPostLocked: true)
        #expect(sanitized.leadingPrimary == .none)
        #expect(sanitized.leadingSecondary == .save)
        #expect(sanitized.trailingPrimary == .upvote)
        #expect(sanitized.trailingSecondary == .downvote)
    }

    @Test
    func sanitizedSwipeActionConfigIsUnchangedWhenNotLocked() {
        let config = SwipeActionConfig.defaultComments
        let sanitized = CommentLockPolicy.sanitizedSwipeActionConfig(config, isPostLocked: false)
        #expect(sanitized == config)
    }
}
