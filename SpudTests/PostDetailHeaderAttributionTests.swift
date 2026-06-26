//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit
import XCTest
@testable import Spud

/// Covers the post-detail header attribution: "in <Community>@host by <Creator>@host",
/// where the community uses its display name (title) and both `@host` suffixes render
/// muted, while the names keep the tap targets.
@MainActor
final class PostDetailHeaderAttributionTests: XCTestCase {
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

    func test_showsDisplayNameAndMutedHosts() {
        XCTAssertEqual(attribution().string, "in News@lemmy.world by Tony@beehaw.org")
    }

    func test_communityHostIsMutedAndNameIsLinked() {
        let s = attribution()
        let ns = s.string as NSString

        let hostRange = ns.range(of: "@lemmy.world")
        let hostColor = s.attribute(.foregroundColor, at: hostRange.location, effectiveRange: nil) as? UIColor
        XCTAssertEqual(hostColor, .tertiaryLabel)

        let nameRange = ns.range(of: "News")
        XCTAssertNotNil(s.attribute(.link, at: nameRange.location, effectiveRange: nil))
        // The muted host suffix is not part of the tap target.
        XCTAssertNil(s.attribute(.link, at: hostRange.location, effectiveRange: nil))
    }

    func test_creatorNameIsLinked() {
        let s = attribution()
        let nameRange = (s.string as NSString).range(of: "Tony")
        XCTAssertNotNil(s.attribute(.link, at: nameRange.location, effectiveRange: nil))
    }

    func test_fallsBackToHandleWhenTitleMissing() {
        XCTAssertTrue(attribution(communityTitle: nil).string.hasPrefix("in news@"))
        XCTAssertTrue(attribution(communityTitle: "   ").string.hasPrefix("in news@"))
    }

    func test_omitsHostWhenActorIdMissing() {
        XCTAssertEqual(attribution(communityActorId: nil).string, "in News by Tony@beehaw.org")
    }
}
