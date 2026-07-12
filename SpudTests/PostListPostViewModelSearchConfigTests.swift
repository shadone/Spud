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
        creatorActorId: String? = "https://lemmy.world/u/alice",
        isNsfw: Bool = false
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
            isNsfw: isNsfw,
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

    // MARK: - NSFW blur (defense-in-depth)

    /// Mirrors `SearchViewController.makePostCell`'s defense-in-depth: when Show-NSFW is
    /// off, the search cell passes `blurNsfw: blurPref || !showNsfw` and forces
    /// `isRevealed: false`, so an NSFW post that somehow slips past the result filter is
    /// still blurred — never a raw NSFW thumbnail to a user who opted out. `blurNsfw`
    /// and `showNsfw` are independent prefs, so blur-off + Show-NSFW-off is reachable.
    @Test
    func nsfwPost_withShowNsfwOff_isForcedBlurred_evenWhenBlurPrefOff() {
        let preferences = PreferencesService.ephemeral()
        preferences.blurNsfw = false // blur preference OFF...
        preferences.showNsfw = false // ...but Show-NSFW also OFF (opted out)

        // The exact values the search cell computes for this pref state.
        let forcedBlur = preferences.blurNsfw || !preferences.showNsfw
        let forcedReveal = preferences.showNsfw && true
        #expect(forcedBlur)
        #expect(forcedReveal == false)

        let vm = PostListPostViewModel(
            row: row(isNsfw: true),
            appearance: AppearanceService(preferencesService: preferences),
            postContentDetector: PostContentDetectorService(),
            blurNsfw: forcedBlur,
            isRevealed: forcedReveal
        )
        #expect(vm.isThumbnailBlurred)
    }

    /// With Show-NSFW on and the blur preference on, an NSFW post is blurred (opted-in
    /// blur), and a non-NSFW post is never blurred regardless of the prefs.
    @Test
    func nsfwPost_withShowNsfwOn_honorsBlurPreference() {
        let preferences = PreferencesService.ephemeral()
        preferences.blurNsfw = true
        preferences.showNsfw = true

        let forcedBlur = preferences.blurNsfw || !preferences.showNsfw
        let appearance = AppearanceService(preferencesService: preferences)
        let detector = PostContentDetectorService()

        let nsfwVm = PostListPostViewModel(
            row: row(isNsfw: true),
            appearance: appearance,
            postContentDetector: detector,
            blurNsfw: forcedBlur,
            isRevealed: preferences.showNsfw && false
        )
        #expect(nsfwVm.isThumbnailBlurred)

        let sfwVm = PostListPostViewModel(
            row: row(isNsfw: false),
            appearance: appearance,
            postContentDetector: detector,
            blurNsfw: forcedBlur
        )
        #expect(sfwVm.isThumbnailBlurred == false)
    }
}
