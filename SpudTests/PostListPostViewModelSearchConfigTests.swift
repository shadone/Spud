//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Covers the Search-only view-model configuration of the shared feed post cell:
/// the author line is built (`@user@instance`) and the trailing vote arrows are
/// suppressed, while the feed's default configuration leaves both off.
@MainActor
struct PostListPostViewModelSearchConfigTests {
    private func row(
        creatorName: String? = "alice",
        creatorActorId: String? = "https://lemmy.world/u/alice"
    ) -> PostListRow {
        PostListRow(
            id: 1,
            serverPostId: 1,
            title: "A searched post",
            body: nil,
            originalPostUrl: "https://lemmy.world/post/1",
            url: nil,
            thumbnailUrl: nil,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            altText: nil,
            communityName: "news",
            communityActorId: "https://lemmy.world/c/news",
            serverCommunityId: 1,
            creatorPersonId: 1,
            creatorName: creatorName,
            creatorActorId: creatorActorId,
            score: 12,
            numberOfComments: 3,
            voteStatus: nil,
            isRead: false,
            isSaved: false,
            isRemoved: false,
            isLocked: false,
            isFeaturedCommunity: false,
            isFeaturedLocal: false,
            isDeleted: false,
            isNsfw: false,
            published: Date(timeIntervalSince1970: 0)
        )
    }

    private func viewModel(
        row: PostListRow,
        showVoteButtonsPreference: Bool = true,
        showsAuthor: Bool = false,
        showVoteButtonsOverride: Bool? = nil
    ) -> PostListPostViewModel {
        let preferences = PreferencesService.ephemeral()
        preferences.showVoteButtons = showVoteButtonsPreference
        return PostListPostViewModel(
            row: row,
            appearance: AppearanceService(preferencesService: preferences),
            postContentDetector: PostContentDetectorService(),
            showsAuthor: showsAuthor,
            showVoteButtonsOverride: showVoteButtonsOverride
        )
    }

    // MARK: - Vote arrows

    @Test
    func searchConfig_suppressesVoteArrows_evenWhenPreferenceOn() {
        let vm = viewModel(
            row: row(),
            showVoteButtonsPreference: true,
            showsAuthor: true,
            showVoteButtonsOverride: false
        )
        #expect(vm.showVoteButtons == false)
    }

    @Test
    func defaultConfig_honorsVoteButtonPreference() {
        // No override: the feed's behavior — follow the appearance preference.
        #expect(viewModel(row: row(), showVoteButtonsPreference: true).showVoteButtons == true)
        #expect(viewModel(row: row(), showVoteButtonsPreference: false).showVoteButtons == false)
    }

    // MARK: - Author line

    @Test
    func searchConfig_buildsAuthorLine() {
        let vm = viewModel(row: row(), showsAuthor: true, showVoteButtonsOverride: false)
        #expect(vm.authorLine?.string == "@alice@lemmy.world")
        #expect(vm.authorAccessibilityLabel?.contains("alice@lemmy.world") == true)
        // The author handle is folded into the cell's spoken label so VoiceOver reads it.
        #expect(vm.accessibilityLabel.contains("alice@lemmy.world"))
    }

    @Test
    func searchConfig_authorLineWithoutHost_isBareHandle() {
        // A creator with no resolvable actor host falls back to the bare handle.
        let vm = viewModel(
            row: row(creatorActorId: nil),
            showsAuthor: true,
            showVoteButtonsOverride: false
        )
        #expect(vm.authorLine?.string == "@alice")
    }

    @Test
    func feedConfig_hasNoAuthorLine() {
        // The feed (showsAuthor defaults to false) never shows the author line, so the
        // feed cell is unchanged.
        let vm = viewModel(row: row())
        #expect(vm.authorLine == nil)
        #expect(vm.authorAccessibilityLabel == nil)
    }
}
