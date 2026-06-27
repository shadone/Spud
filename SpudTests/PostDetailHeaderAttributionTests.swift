//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Covers the post-detail header attribution: "in <Community>@host by <Creator>@host",
/// where the community uses its display name (title) and both `@host` suffixes render
/// muted, while the names keep the tap targets.
@MainActor
struct PostDetailHeaderAttributionTests {
    private func attribution(
        communityName: String = "news",
        communityTitle: String? = "News",
        communityActorId: String? = "https://lemmy.world/c/news",
        creatorName: String = "Tony",
        creatorInstanceActorId: String = "https://beehaw.org"
    ) -> NSAttributedString {
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
            communityName: communityName,
            communityTitle: communityTitle,
            communityActorId: communityActorId,
            serverCommunityId: 1,
            creatorName: creatorName,
            creatorPersonId: 1,
            creatorInstanceActorId: creatorInstanceActorId,
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
            published: Date(timeIntervalSince1970: 0)
        )
        let vm = PostDetailHeaderViewModel(
            row: row,
            appearance: AppearanceService(preferencesService: PreferencesService()),
            postContentDetector: PostContentDetectorService()
        )
        return vm.attribution
    }

    @Test
    func showsDisplayNameAndMutedHosts() {
        #expect(attribution().string == "in News@lemmy.world by Tony@beehaw.org")
    }

    @Test
    func communityHostIsMutedAndWholeHandleIsLinked() {
        let s = attribution()
        let ns = s.string as NSString

        let hostRange = ns.range(of: "@lemmy.world")
        // Host stays muted...
        let hostColor = s.attribute(.foregroundColor, at: hostRange.location, effectiveRange: nil) as? UIColor
        #expect(hostColor == .tertiaryLabel)

        // ...but the whole "News@lemmy.world" handle is the tap target: name and host
        // carry the same link (so they read as one link range).
        let nameRange = ns.range(of: "News")
        let nameLink = s.attribute(.link, at: nameRange.location, effectiveRange: nil) as? URL
        let hostLink = s.attribute(.link, at: hostRange.location, effectiveRange: nil) as? URL
        #expect(nameLink != nil)
        #expect(nameLink == hostLink)
    }

    @Test
    func creatorHandleIsLinked() {
        let s = attribution()
        let ns = s.string as NSString
        let nameLink = s.attribute(.link, at: ns.range(of: "Tony").location, effectiveRange: nil) as? URL
        let hostLink = s.attribute(.link, at: ns.range(of: "@beehaw.org").location, effectiveRange: nil) as? URL
        #expect(nameLink != nil)
        #expect(nameLink == hostLink)
    }

    @Test
    func fallsBackToHandleWhenTitleMissing() {
        #expect(attribution(communityTitle: nil).string.hasPrefix("in news@"))
        #expect(attribution(communityTitle: "   ").string.hasPrefix("in news@"))
    }

    @Test
    func omitsHostWhenActorIdMissing() {
        #expect(attribution(communityActorId: nil).string == "in News by Tony@beehaw.org")
    }
}
