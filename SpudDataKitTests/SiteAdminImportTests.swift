//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import Testing
@testable import SpudDataKit

struct SiteAdminImportTests {
    @Test
    func upsertSite_storesAdminsInOrder() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let response = Self.makeGetSiteResponse(
            actorId: "https://lemmy.world",
            admins: [
                Self.personView(name: "ruud", display: "Ruud", actorId: "https://lemmy.world/u/ruud"),
                Self.personView(name: "milan", display: nil, actorId: "https://lemmy.world/u/milan"),
            ]
        )

        let (_, siteId) = try await appDatabase.upsertSite(from: response)

        let admins = try await appDatabase.writer.read { db in
            try SiteAdminRecord
                .filter(SiteAdminRecord.Columns.siteId == siteId)
                .order(SiteAdminRecord.Columns.ordinal)
                .fetchAll(db)
        }
        #expect(admins.map(\.personName) == ["ruud", "milan"])
        #expect(admins.map(\.ordinal) == [0, 1])
        #expect(admins[0].displayName == "Ruud")
        #expect(admins[1].displayName == nil)
    }

    @Test
    func upsertSite_replacesAdminsOnReimport() async throws {
        let appDatabase = try AppDatabase.inMemory()
        _ = try await appDatabase.upsertSite(from: Self.makeGetSiteResponse(
            actorId: "https://lemmy.world",
            admins: [Self.personView(name: "old", display: nil, actorId: "https://lemmy.world/u/old")]
        ))
        let (_, siteId) = try await appDatabase.upsertSite(from: Self.makeGetSiteResponse(
            actorId: "https://lemmy.world",
            admins: [Self.personView(name: "new", display: nil, actorId: "https://lemmy.world/u/new")]
        ))

        let names = try await appDatabase.writer.read { db in
            try SiteAdminRecord.filter(SiteAdminRecord.Columns.siteId == siteId).fetchAll(db).map(\.personName)
        }
        #expect(names == ["new"])
    }
}

extension SiteAdminImportTests {
    static func personView(
        name: String,
        display: String?,
        actorId: String
    ) -> Components.Schemas.PersonView {
        let date = Date(timeIntervalSince1970: 1_685_577_784)
        let person = Components.Schemas.Person(
            id: 1,
            name: name,
            display_name: display,
            avatar: nil,
            banned: false,
            published: date,
            updated: nil,
            actor_id: actorId,
            bio: nil,
            local: true,
            banner: nil,
            deleted: false,
            matrix_user_id: nil,
            bot_account: false,
            ban_expires: nil,
            instance_id: 1
        )
        return Components.Schemas.PersonView(
            person: person,
            counts: .init(
                person_id: person.id,
                post_count: 0,
                comment_count: 0
            ),
            is_admin: true
        )
    }

    static func makeGetSiteResponse(
        actorId: String,
        admins: [Components.Schemas.PersonView]
    ) -> Components.Schemas.GetSiteResponse {
        let response = Components.Schemas.GetSiteResponse.fake(myUser: false)
        // Patch the actor_id on the site to match the requested instance.
        let view = response.site_view
        let date = Date(timeIntervalSince1970: 1_685_577_784)
        let site = Components.Schemas.Site(
            id: view.site.id,
            name: view.site.name,
            published: view.site.published,
            actor_id: actorId,
            last_refreshed_at: date,
            inbox_url: view.site.inbox_url,
            public_key: view.site.public_key,
            instance_id: view.site.instance_id
        )
        let patchedView = Components.Schemas.SiteView(
            site: site,
            local_site: view.local_site,
            local_site_rate_limit: view.local_site_rate_limit,
            counts: view.counts
        )
        return Components.Schemas.GetSiteResponse(
            site_view: patchedView,
            admins: admins,
            version: response.version,
            my_user: response.my_user,
            all_languages: response.all_languages,
            discussion_languages: response.discussion_languages,
            taglines: response.taglines,
            custom_emojis: response.custom_emojis,
            blocked_urls: response.blocked_urls
        )
    }
}
