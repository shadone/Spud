//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Lemmy.GetSiteResponse {
    /// A `getSite` response whose `my_user` reflects the given moderated
    /// communities and admin flag. Everything else is minimal boilerplate so
    /// the response decodes; the moderation-capability resolution only reads
    /// `my_user.moderates` and `my_user.local_user_view.local_user.admin`.
    ///
    /// Pass `myUser: false` to model a response with no `my_user` (e.g. a
    /// signed-out fetch), which resolves to `.none`.
    static func fake(
        moderates: [Lemmy.Community] = [],
        isAdmin: Bool = false,
        myUser: Bool = true
    ) -> Lemmy.GetSiteResponse {
        let person = Lemmy.Person.fake
        let date = Date(timeIntervalSince1970: 1_685_577_784)

        let site = Lemmy.Site(
            id: 1,
            name: "Example",
            published: date,
            actor_id: "https://example.com",
            last_refreshed_at: date,
            inbox_url: "https://example.com/inbox",
            public_key: "fake-public-key",
            instance_id: 1
        )
        let localSite = Lemmy.LocalSite(
            id: 1,
            site_id: 1,
            site_setup: true,
            enable_downvotes: true,
            enable_nsfw: false,
            community_creation_admin_only: false,
            require_email_verification: false,
            private_instance: false,
            default_theme: "browser",
            default_post_listing_type: .Local,
            hide_modlog_mod_names: false,
            application_email_admins: false,
            actor_name_max_length: 20,
            federation_enabled: true,
            captcha_enabled: false,
            captcha_difficulty: "medium",
            published: date,
            registration_mode: .Open,
            reports_email_admins: false,
            federation_signed_fetch: false,
            default_post_listing_mode: .List,
            default_sort_type: .Active
        )
        let rateLimit = Lemmy.LocalSiteRateLimit(
            local_site_id: 1,
            message: 999,
            message_per_second: 60,
            post: 999,
            post_per_second: 600,
            register: 999,
            register_per_second: 3600,
            image: 999,
            image_per_second: 3600,
            comment: 999,
            comment_per_second: 600,
            search: 999,
            search_per_second: 600,
            published: date,
            import_user_settings: 999,
            import_user_settings_per_second: 3600
        )
        let siteAggregates = Lemmy.SiteAggregates(
            site_id: 1,
            users: 0,
            posts: 0,
            comments: 0,
            communities: 0,
            users_active_day: 0,
            users_active_week: 0,
            users_active_month: 0,
            users_active_half_year: 0
        )
        let siteView = Lemmy.SiteView(
            site: site,
            local_site: localSite,
            local_site_rate_limit: rateLimit,
            counts: siteAggregates
        )

        let myUserInfo: Lemmy.MyUserInfo? = myUser
            ? .init(
                local_user_view: .init(
                    local_user: localUser(personId: person.id, isAdmin: isAdmin),
                    local_user_vote_display_mode: .init(
                        local_user_id: 1,
                        score: true,
                        upvotes: true,
                        downvotes: true,
                        upvote_percentage: false
                    ),
                    person: person,
                    counts: .init(person_id: person.id, post_count: 0, comment_count: 0)
                ),
                follows: [],
                moderates: moderates.map { .init(community: $0, moderator: person) },
                community_blocks: [],
                instance_blocks: [],
                person_blocks: [],
                discussion_languages: []
            )
            : nil

        return .init(
            site_view: siteView,
            admins: [],
            version: "0.19.0",
            my_user: myUserInfo,
            all_languages: [],
            discussion_languages: [],
            taglines: [],
            custom_emojis: [],
            blocked_urls: []
        )
    }

    private static func localUser(
        personId: Lemmy.PersonID,
        isAdmin: Bool
    ) -> Lemmy.LocalUser {
        .init(
            id: 1,
            person_id: personId,
            show_nsfw: false,
            theme: "browser",
            default_sort_type: .Active,
            default_listing_type: .Local,
            interface_language: "en",
            show_avatars: true,
            send_notifications_to_email: false,
            show_scores: true,
            show_bot_accounts: true,
            show_read_posts: true,
            email_verified: false,
            accepted_application: true,
            open_links_in_new_tab: false,
            blur_nsfw: true,
            auto_expand: false,
            infinite_scroll_enabled: true,
            admin: isAdmin,
            post_listing_mode: .List,
            totp_2fa_enabled: false,
            enable_keyboard_navigation: false,
            enable_animated_images: true,
            collapse_bot_comments: false,
            last_donation_notification: Date(timeIntervalSince1970: 1_685_577_784)
        )
    }
}
