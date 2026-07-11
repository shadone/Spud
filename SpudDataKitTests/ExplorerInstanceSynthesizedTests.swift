//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

/// Tests the pure `SiteInfo` -> `ExplorerInstanceRecord` synthesizer used to open
/// the in-app instance screen for a Lemmy-API-compatible host (PieFed included)
/// that is not in the bundled Explorer directory.
///
/// NOTE (Phase 6 neutral migration): `synthesized(from:host:)` now consumes the
/// version-neutral ``LemmyKit/SiteInfo``, which carries only the site's public
/// identity + aggregate counts — NOT the v3 `LocalSite` policy block
/// (registration mode, NSFW, downvotes, private-instance, federation flags). Those
/// have no neutral source, so the synthesizer fills them with fixed optimistic
/// defaults; the former `mapsPolicyFlags` / `mapsRegistrationMode` tests (which
/// drove those flags off the response) are replaced by
/// `policyFlagsUseOptimisticDefaults` below.
struct ExplorerInstanceSynthesizedTests {
    /// A `SiteInfo` shaped like a real `fedinsfw.app` (PieFed) probe: identity +
    /// icon/banner + usage tallies. `version` rides on the `SiteInfo`, not the
    /// `Site`.
    static func makeSiteInfo(
        actorId: String = "https://fedinsfw.app",
        name: String = "FediNSFW",
        description: String? = "An adult-content instance",
        icon: String? = "https://fedinsfw.app/pictrs/image/icon.png",
        banner: String? = "https://fedinsfw.app/pictrs/image/banner.png",
        users: Int64 = 1234,
        usersActiveMonth: Int64 = 321,
        usersActiveHalfYear: Int64 = 654,
        communities: Int64 = 42,
        posts: Int64 = 9876,
        comments: Int64 = 54321,
        version: String = "0.19.5"
    ) -> LemmyKit.SiteInfo {
        let date = Date(timeIntervalSince1970: 1_685_577_784)
        let site = Lemmy.Site(
            id: 1,
            name: name,
            summary: description,
            sidebar: "Sidebar text",
            iconUrl: icon,
            bannerUrl: banner,
            apId: actorId,
            publishedAt: date,
            updatedAt: nil,
            posts: posts,
            comments: comments,
            communities: communities,
            users: users,
            usersActiveDay: 11,
            usersActiveWeek: 22,
            usersActiveMonth: usersActiveMonth,
            usersActiveHalfYear: usersActiveHalfYear
        )
        return SiteInfo(site: site, version: version)
    }

    @Test
    func mapsIdentityAndStats() {
        let siteInfo = Self.makeSiteInfo()

        let record = ExplorerInstanceRecord.synthesized(from: siteInfo, host: "fedinsfw.app")

        #expect(record.id == nil)
        #expect(record.baseurl == "fedinsfw.app")
        #expect(record.name == "FediNSFW")
        #expect(record.url == "https://fedinsfw.app")
        #expect(record.descriptionText == "An adult-content instance")
        #expect(record.version == "0.19.5")
        #expect(record.iconUrl == "https://fedinsfw.app/pictrs/image/icon.png")
        #expect(record.bannerUrl == "https://fedinsfw.app/pictrs/image/banner.png")
    }

    @Test
    func mapsUsageCounts() {
        let siteInfo = Self.makeSiteInfo()

        let record = ExplorerInstanceRecord.synthesized(from: siteInfo, host: "fedinsfw.app")

        #expect(record.usersTotal == 1234)
        #expect(record.usersActiveMonth == 321)
        #expect(record.usersActiveHalfYear == 654)
        #expect(record.numberOfCommunities == 42)
        #expect(record.numberOfPosts == 9876)
        #expect(record.numberOfComments == 54321)
    }

    /// The neutral `SiteInfo` carries no `LocalSite` policy, so the synthesizer
    /// can't know the registration mode and reports `.unknown` (not a misleading
    /// "open"); the remaining flags use benign defaults. This replaces the former
    /// input-driven `mapsPolicyFlags` / `mapsRegistrationMode` tests (Phase 6
    /// follow-up: recover real policy from a neutral local-site source).
    @Test
    func policyFlagsUseNeutralDefaults() {
        let record = ExplorerInstanceRecord.synthesized(from: Self.makeSiteInfo(), host: "fedinsfw.app")

        #expect(record.registrationMode == .unknown)
        #expect(record.isOpenRegistration == false)
        #expect(record.isNsfw == false)
        #expect(record.allowsDownvotes == true)
        #expect(record.isPrivate == false)
        #expect(record.federationEnabled == true)
    }

    @Test
    func leavesDirectoryOnlyFieldsAtDefaults() {
        let siteInfo = Self.makeSiteInfo()

        let record = ExplorerInstanceRecord.synthesized(from: siteInfo, host: "fedinsfw.app")

        // Fields with no site-info analogue stay at sensible defaults so a
        // synthesized record never claims directory-quality metadata.
        #expect(record.uptimeAllTime == nil)
        #expect(record.latency == nil)
        #expect(record.uptimeStatus == nil)
        #expect(record.score == 0)
        #expect(record.isSuspicious == false)
        #expect(record.langs == nil)
        #expect(record.tags == nil)
        #expect(record.blocksIncoming == nil)
        #expect(record.blocksOutgoing == nil)
    }

    @Test
    func toleratesMissingOptionalIdentity() {
        let siteInfo = Self.makeSiteInfo(description: nil, icon: nil, banner: nil)

        let record = ExplorerInstanceRecord.synthesized(from: siteInfo, host: "fedinsfw.app")

        #expect(record.descriptionText == nil)
        #expect(record.iconUrl == nil)
        #expect(record.bannerUrl == nil)
        #expect(record.name == "FediNSFW")
    }
}
