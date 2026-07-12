//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Covers the low-noise author-status marker on the feed cell: the inline red
/// `person.fill.xmark` is added to the metadata line ONLY for a suspended or
/// community-banned author (never mod / admin / bot), and the matching ban
/// phrase is folded into the cell's spoken subtitle so VoiceOver announces it.
@MainActor
struct PostListPostViewModelAuthorStatusTests {
    /// Number of inline attachments (SF Symbols) in an attributed string — each
    /// renders as one object-replacement character (U+FFFC) in `.string`. The
    /// warning marker adds exactly one over the baseline metadata icons.
    private func attachmentCount(_ string: NSAttributedString) -> Int {
        string.string.unicodeScalars.filter { $0 == "\u{FFFC}" }.count
    }

    private func viewModel(
        isCreatorModerator: Bool = false,
        isCreatorAdmin: Bool = false,
        isCreatorBannedFromCommunity: Bool = false,
        isCreatorSiteBanned: Bool = false,
        isCreatorBot: Bool = false
    ) -> PostListPostViewModel {
        let row = PostListRow(
            id: 1,
            serverPostId: 1,
            title: "t",
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
            creatorName: "alice",
            creatorActorId: "https://lemmy.world/u/alice",
            score: 1,
            numberOfComments: 0,
            voteStatus: nil,
            isRead: false,
            isSaved: false,
            isRemoved: false,
            isLocked: false,
            isFeaturedCommunity: false,
            isFeaturedLocal: false,
            isDeleted: false,
            isNsfw: false,
            isCreatorModerator: isCreatorModerator,
            isCreatorAdmin: isCreatorAdmin,
            isCreatorBannedFromCommunity: isCreatorBannedFromCommunity,
            isCreatorSiteBanned: isCreatorSiteBanned,
            isCreatorBot: isCreatorBot,
            isCreatorAccountDeleted: false,
            published: Date(timeIntervalSince1970: 0)
        )
        return PostListPostViewModel(
            row: row,
            appearance: AppearanceService(preferencesService: PreferencesService.ephemeral()),
            postContentDetector: PostContentDetectorService()
        )
    }

    // MARK: - Visible marker

    @Test
    func siteBannedAuthor_addsOneWarningMarker() {
        let baseline = attachmentCount(viewModel().subtitle)
        #expect(attachmentCount(viewModel(isCreatorSiteBanned: true).subtitle) == baseline + 1)
    }

    @Test
    func communityBannedAuthor_addsOneWarningMarker() {
        let baseline = attachmentCount(viewModel().subtitle)
        #expect(attachmentCount(viewModel(isCreatorBannedFromCommunity: true).subtitle) == baseline + 1)
    }

    @Test
    func benignRoles_addNoMarker() {
        let baseline = attachmentCount(viewModel().subtitle)
        #expect(attachmentCount(viewModel(isCreatorModerator: true).subtitle) == baseline)
        #expect(attachmentCount(viewModel(isCreatorAdmin: true).subtitle) == baseline)
        #expect(attachmentCount(viewModel(isCreatorBot: true).subtitle) == baseline)
    }

    // MARK: - Spoken subtitle

    @Test
    func spokenSubtitle_announcesBanButNotBenignRoles() {
        #expect(viewModel(isCreatorSiteBanned: true).subtitleAccessibilityLabel.contains("suspended site-wide"))
        #expect(viewModel(isCreatorBannedFromCommunity: true).subtitleAccessibilityLabel.contains("banned from this community"))

        // The feed stays quiet about benign roles in speech too.
        let mod = viewModel(isCreatorModerator: true).subtitleAccessibilityLabel
        #expect(!mod.contains("suspended site-wide"))
        #expect(!mod.contains("banned from this community"))

        // An ordinary author announces neither.
        let ordinary = viewModel().subtitleAccessibilityLabel
        #expect(!ordinary.contains("suspended"))
        #expect(!ordinary.contains("banned"))
    }
}
