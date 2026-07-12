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
        let siteInfo = Self.makeSiteInfo(
            actorId: "https://lemmy.world",
            admins: [
                Self.admin(name: "ruud", display: "Ruud", actorId: "https://lemmy.world/u/ruud"),
                Self.admin(name: "milan", display: nil, actorId: "https://lemmy.world/u/milan"),
            ]
        )

        let (_, siteId) = try await appDatabase.upsertSite(from: siteInfo)

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
        _ = try await appDatabase.upsertSite(from: Self.makeSiteInfo(
            actorId: "https://lemmy.world",
            admins: [Self.admin(name: "old", display: nil, actorId: "https://lemmy.world/u/old")]
        ))
        let (_, siteId) = try await appDatabase.upsertSite(from: Self.makeSiteInfo(
            actorId: "https://lemmy.world",
            admins: [Self.admin(name: "new", display: nil, actorId: "https://lemmy.world/u/new")]
        ))

        let names = try await appDatabase.writer.read { db in
            try SiteAdminRecord.filter(SiteAdminRecord.Columns.siteId == siteId).fetchAll(db).map(\.personName)
        }
        #expect(names == ["new"])
    }
}

extension SiteAdminImportTests {
    /// A neutral admin `Person`. `upsertSite` now consumes a ``LemmyKit/SiteInfo``
    /// whose `admins` are bare neutral ``LemmyKit/Person`` values (v4 flattened the
    /// admin identity off the composed `PersonView`).
    static func admin(
        name: String,
        display: String?,
        actorId: String
    ) -> Lemmy.Person {
        Lemmy.Person(
            id: 1,
            name: name,
            displayName: display,
            avatarUrl: nil,
            bannerUrl: nil,
            bio: nil,
            apId: actorId,
            matrixUserId: nil,
            botAccount: false,
            deleted: false,
            local: true,
            publishedAt: Date(timeIntervalSince1970: 1_685_577_784),
            updatedAt: nil,
            postCount: 0,
            commentCount: 0
        )
    }

    static func makeSiteInfo(
        actorId: String,
        admins: [Lemmy.Person]
    ) -> LemmyKit.SiteInfo {
        let date = Date(timeIntervalSince1970: 1_685_577_784)
        let site = Lemmy.Site(
            id: 1,
            name: "Example",
            summary: nil,
            sidebar: nil,
            iconUrl: nil,
            bannerUrl: nil,
            apId: actorId,
            publishedAt: date,
            updatedAt: nil,
            posts: 0,
            comments: 0,
            communities: 0,
            users: 0,
            usersActiveDay: 0,
            usersActiveWeek: 0,
            usersActiveMonth: 0,
            usersActiveHalfYear: 0
        )
        return SiteInfo(site: site, version: "0.19.0", admins: admins)
    }
}
