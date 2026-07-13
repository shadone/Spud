//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
@testable import Spud

@MainActor
struct PostDetailCommentViewModelAccessibilityTests {
    // MARK: - Helpers

    private func makeRow() -> PostDetailCommentRow {
        PostDetailCommentRow(
            id: 1,
            position: 1,
            depth: 1,
            serverCommentId: 1,
            body: "Test comment body.",
            originalCommentUrl: "https://lemmy.world/comment/1",
            score: 42,
            voteStatus: nil,
            isSaved: false,
            isRemoved: false,
            isDistinguished: false,
            isDeleted: false,
            isCreatorModerator: false,
            isCreatorAdmin: false,
            isCreatorBannedFromCommunity: false,
            isCreatorBlocked: false,
            isCreatorSiteBanned: false,
            isCreatorBot: false,
            isCreatorAccountDeleted: false,
            removedReason: nil,
            published: Date(timeIntervalSinceNow: -3600),
            creatorName: "alice",
            creatorPersonId: 1,
            creatorActorId: "https://lemmy.world",
            moreChildCount: nil,
            moreParentId: nil,
            childCount: nil
        )
    }

    private func makeViewModel(isNew: Bool) -> PostDetailCommentViewModel {
        let appearance = AppearanceService(preferencesService: PreferencesService())
        return PostDetailCommentViewModel(
            row: makeRow(),
            appearance: appearance,
            isNew: isNew
        )
    }

    // MARK: - Tests

    @Test
    func isNewAddsVoiceOverPhrase() {
        let vm = makeViewModel(isNew: true)
        #expect(
            (vm.subtitleAccessibilityLabel ?? "").contains("New comment"),
            "subtitleAccessibilityLabel should contain 'New comment' when isNew is true"
        )
    }

    @Test
    func isNotNewDoesNotAddVoiceOverPhrase() {
        let vm = makeViewModel(isNew: false)
        #expect(
            !((vm.subtitleAccessibilityLabel ?? "").contains("New comment")),
            "subtitleAccessibilityLabel should not contain 'New comment' when isNew is false"
        )
    }

    @Test
    func collapsedWithNewDescendantsAddsNewClauseAndExposesCount() {
        let appearance = AppearanceService(preferencesService: PreferencesService())
        let vm = PostDetailCommentViewModel(
            row: makeRow(),
            appearance: appearance,
            isCollapsed: true,
            collapsedDescendantCount: 22,
            collapsedNewDescendantCount: 5
        )
        let label = vm.subtitleAccessibilityLabel ?? ""
        #expect(label.contains("22 hidden"), "expected hidden count in: \(label)")
        #expect(label.contains("5 new"), "expected new count in: \(label)")
        #expect(vm.collapsedNewDescendantCount == 5)
    }

    @Test
    func collapsedWithZeroNewDescendantsHasNoNewCount() {
        let appearance = AppearanceService(preferencesService: PreferencesService())
        let vm = PostDetailCommentViewModel(
            row: makeRow(),
            appearance: appearance,
            isCollapsed: true,
            collapsedDescendantCount: 8,
            collapsedNewDescendantCount: 0
        )
        #expect(vm.collapsedNewDescendantCount == nil)
        #expect(!((vm.subtitleAccessibilityLabel ?? "").contains(" new")))
    }
}
