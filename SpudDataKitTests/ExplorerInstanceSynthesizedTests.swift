//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

/// Tests the pure `GetSiteResponse` -> `ExplorerInstanceRecord` synthesizer used
/// to open the in-app instance screen for a Lemmy-API-compatible host (PieFed
/// included) that is not in the bundled Explorer directory.
struct ExplorerInstanceSynthesizedTests {
    /// A `getSite` response shaped like a real `fedinsfw.app` (PieFed) probe:
    /// `site_view.site` carries identity + icon/banner, `site_view.counts`
    /// carries the usage tallies, `local_site` carries the policy flags.
    static func makeResponse(
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
        version: String = "0.19.5",
        registrationMode: Lemmy.RegistrationMode = .Open,
        enableNsfw: Bool = true,
        enableDownvotes: Bool = false,
        privateInstance: Bool = false,
        federationEnabled: Bool = true
    ) -> Lemmy.GetSiteResponse {
        let base = Lemmy.GetSiteResponse.fake(myUser: false)
        let date = Date(timeIntervalSince1970: 1_685_577_784)

        let site = Lemmy.Site(
            id: 1,
            name: name,
            sidebar: "Sidebar text",
            published: date,
            icon: icon,
            banner: banner,
            description: description,
            actor_id: actorId,
            last_refreshed_at: date,
            inbox_url: "\(actorId)/inbox",
            public_key: "fake-public-key",
            instance_id: 1
        )

        let localSite = Lemmy.LocalSite(
            id: 1,
            site_id: 1,
            site_setup: true,
            enable_downvotes: enableDownvotes,
            enable_nsfw: enableNsfw,
            community_creation_admin_only: false,
            require_email_verification: false,
            private_instance: privateInstance,
            default_theme: "browser",
            default_post_listing_type: .Local,
            hide_modlog_mod_names: false,
            application_email_admins: false,
            actor_name_max_length: 20,
            federation_enabled: federationEnabled,
            captcha_enabled: false,
            captcha_difficulty: "medium",
            published: date,
            registration_mode: registrationMode,
            reports_email_admins: false,
            federation_signed_fetch: false,
            default_post_listing_mode: .List,
            default_sort_type: .Active
        )

        let counts = Lemmy.SiteAggregates(
            site_id: 1,
            users: users,
            posts: posts,
            comments: comments,
            communities: communities,
            users_active_day: 11,
            users_active_week: 22,
            users_active_month: usersActiveMonth,
            users_active_half_year: usersActiveHalfYear
        )

        let view = Lemmy.SiteView(
            site: site,
            local_site: localSite,
            local_site_rate_limit: base.site_view.local_site_rate_limit,
            counts: counts
        )

        return Lemmy.GetSiteResponse(
            site_view: view,
            admins: base.admins,
            version: version,
            my_user: base.my_user,
            all_languages: base.all_languages,
            discussion_languages: base.discussion_languages,
            taglines: base.taglines,
            custom_emojis: base.custom_emojis,
            blocked_urls: base.blocked_urls
        )
    }

    @Test
    func mapsIdentityAndStats() {
        let response = Self.makeResponse()

        let record = ExplorerInstanceRecord.synthesized(from: response, host: "fedinsfw.app")

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
        let response = Self.makeResponse()

        let record = ExplorerInstanceRecord.synthesized(from: response, host: "fedinsfw.app")

        #expect(record.usersTotal == 1234)
        #expect(record.usersActiveMonth == 321)
        #expect(record.usersActiveHalfYear == 654)
        #expect(record.numberOfCommunities == 42)
        #expect(record.numberOfPosts == 9876)
        #expect(record.numberOfComments == 54321)
    }

    @Test
    func mapsPolicyFlags() {
        let response = Self.makeResponse(
            registrationMode: .Open,
            enableNsfw: true,
            enableDownvotes: false,
            privateInstance: false,
            federationEnabled: true
        )

        let record = ExplorerInstanceRecord.synthesized(from: response, host: "fedinsfw.app")

        #expect(record.registrationMode == .open)
        #expect(record.isOpenRegistration == true)
        #expect(record.isNsfw == true)
        #expect(record.allowsDownvotes == false)
        #expect(record.isPrivate == false)
        #expect(record.federationEnabled == true)
    }

    @Test(arguments: [
        (Lemmy.RegistrationMode.Closed, ExplorerRegistrationMode.closed, false),
        (.RequireApplication, .requireApplication, false),
        (.Open, .open, true),
    ])
    func mapsRegistrationMode(
        apiMode: Lemmy.RegistrationMode,
        expected: ExplorerRegistrationMode,
        expectedOpen: Bool
    ) {
        let response = Self.makeResponse(registrationMode: apiMode)

        let record = ExplorerInstanceRecord.synthesized(from: response, host: "fedinsfw.app")

        #expect(record.registrationMode == expected)
        #expect(record.isOpenRegistration == expectedOpen)
    }

    @Test
    func leavesDirectoryOnlyFieldsAtDefaults() {
        let response = Self.makeResponse()

        let record = ExplorerInstanceRecord.synthesized(from: response, host: "fedinsfw.app")

        // Fields with no /api/v3/site analogue stay at sensible defaults so a
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
        let response = Self.makeResponse(description: nil, icon: nil, banner: nil)

        let record = ExplorerInstanceRecord.synthesized(from: response, host: "fedinsfw.app")

        #expect(record.descriptionText == nil)
        #expect(record.iconUrl == nil)
        #expect(record.bannerUrl == nil)
        #expect(record.name == "FediNSFW")
    }
}
