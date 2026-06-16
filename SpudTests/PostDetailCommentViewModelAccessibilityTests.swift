//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import XCTest
@testable import Spud

@MainActor
final class PostDetailCommentViewModelAccessibilityTests: XCTestCase {
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
            creatorInstanceActorId: "https://lemmy.world",
            moreChildCount: nil,
            moreParentId: nil
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

    func testIsNewAddsVoiceOverPhrase() {
        let vm = makeViewModel(isNew: true)
        XCTAssertTrue(
            (vm.subtitleAccessibilityLabel ?? "").contains("New comment"),
            "subtitleAccessibilityLabel should contain 'New comment' when isNew is true"
        )
    }

    func testIsNotNewDoesNotAddVoiceOverPhrase() {
        let vm = makeViewModel(isNew: false)
        XCTAssertFalse(
            (vm.subtitleAccessibilityLabel ?? "").contains("New comment"),
            "subtitleAccessibilityLabel should not contain 'New comment' when isNew is false"
        )
    }
}
