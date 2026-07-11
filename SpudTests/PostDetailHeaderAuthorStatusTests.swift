//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Covers how the post-detail header view model surfaces the post author's
/// role/status: the `PostAuthorStatus` pills it exposes to the cell, the folded
/// VoiceOver phrase, and the "[deleted]" author rendering in the byline (name
/// swapped, profile link suppressed, home host dropped).
@MainActor
struct PostDetailHeaderAuthorStatusTests {
    private func viewModel(
        creatorName: String = "Tony",
        creatorActorId: String? = "https://beehaw.org/u/Tony",
        isCreatorModerator: Bool = false,
        isCreatorAdmin: Bool = false,
        isCreatorBannedFromCommunity: Bool = false,
        isCreatorSiteBanned: Bool = false,
        creatorBanExpires: Date? = nil,
        isCreatorBot: Bool = false,
        isCreatorAccountDeleted: Bool = false
    ) -> PostDetailHeaderViewModel {
        let row = PostDetailHeaderRow(
            id: 1,
            serverPostId: 1,
            title: "t",
            body: nil,
            originalPostUrl: "https://lemmy.world/post/1",
            url: nil,
            thumbnailUrl: nil,
            imageWidth: nil,
            imageHeight: nil,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            altText: nil,
            communityName: "news",
            communityTitle: "News",
            communityActorId: "https://lemmy.world/c/news",
            serverCommunityId: 1,
            creatorName: creatorName,
            creatorPersonId: 1,
            creatorActorId: creatorActorId,
            score: 0,
            numberOfComments: 0,
            voteStatus: nil,
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
            creatorBanExpires: creatorBanExpires,
            isCreatorBot: isCreatorBot,
            isCreatorAccountDeleted: isCreatorAccountDeleted,
            published: Date(timeIntervalSince1970: 0)
        )
        return PostDetailHeaderViewModel(
            row: row,
            appearance: AppearanceService(preferencesService: PreferencesService.ephemeral()),
            postContentDetector: PostContentDetectorService()
        )
    }

    // MARK: - Badges

    @Test
    func ordinaryAuthor_hasNoBadges() {
        let vm = viewModel()
        #expect(vm.badges.isEmpty)
        #expect(vm.authorStatusAccessibilityLabel == nil)
    }

    @Test
    func bannedAuthor_exposesSuspendedPillAndPhrase() {
        let vm = viewModel(isCreatorSiteBanned: true)
        #expect(vm.badges == [
            AuthorBadge(text: "SUSPENDED", symbolName: "person.fill.xmark", usesAccent: false, color: .systemRed, solid: false),
        ])
        #expect(vm.authorStatusAccessibilityLabel == "suspended site-wide")
    }

    @Test
    func adminModAuthor_exposesOrderedPillsAndFoldedPhrase() {
        let vm = viewModel(isCreatorModerator: true, isCreatorAdmin: true)
        #expect(vm.badges == [
            AuthorBadge(text: "MOD", symbolName: nil, usesAccent: false, color: .systemGreen, solid: false),
            AuthorBadge(text: "ADMIN", symbolName: nil, usesAccent: false, color: .systemIndigo, solid: false),
        ])
        // The pills stay decorative; the byline speaks the folded phrase.
        #expect(vm.authorStatusAccessibilityLabel == "moderator, admin")
    }

    // MARK: - "[deleted]" author

    @Test
    func deletedAuthor_rendersDeletedNameWithNoLinkOrHost() {
        let vm = viewModel(isCreatorAccountDeleted: true)
        // The byline swaps the name for "[deleted]" and drops the home host.
        #expect(vm.attribution.string == "in News@lemmy.world by [deleted]")

        let ns = vm.attribution.string as NSString
        let deletedRange = ns.range(of: "[deleted]")
        // No profile link, and a quiet tertiary color.
        let link = vm.attribution.attribute(.link, at: deletedRange.location, effectiveRange: nil) as? URL
        #expect(link == nil)
        let color = vm.attribution.attribute(.foregroundColor, at: deletedRange.location, effectiveRange: nil) as? UIColor
        #expect(color == .tertiaryLabel)
    }

    @Test
    func nonDeletedAuthor_keepsProfileLink() {
        let vm = viewModel()
        let ns = vm.attribution.string as NSString
        let nameLink = vm.attribution.attribute(.link, at: ns.range(of: "Tony").location, effectiveRange: nil) as? URL
        #expect(nameLink != nil)
    }
}
