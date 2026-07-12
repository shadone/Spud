//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit

public extension AppDatabase {
    /// Public mirror entry point for fetchPersonInfo. Upserts the person row
    /// from a fresh `PersonView`. Skipped silently if the site is not yet in
    /// AppDatabase.
    func upsertPerson(
        from view: Lemmy.PersonView,
        siteId: Int64
    ) async throws {
        try await writer.write { db in
            _ = try Self.upsertPerson(from: view, siteId: siteId, in: db)
        }
    }
}

extension AppDatabase {
    /// Upserts the person row for `siteId` keyed on the server-assigned
    /// `model.id`. Returns the resolved row id. Caller must already be inside
    /// a write transaction.
    static func upsertPerson(
        from model: Lemmy.Person,
        siteId: Int64,
        in db: Database
    ) throws -> Int64 {
        let now = Date()

        if var existing = try PersonRecord
            .filter(Column("siteId") == siteId)
            .filter(Column("personId") == Int64(model.id))
            .fetchOne(db)
        {
            apply(model: model, to: &existing, now: now)
            try existing.update(db)
            return existing.id!
        }

        var record = PersonRecord(
            siteId: siteId,
            personId: Int64(model.id),
            createdAt: now,
            updatedAt: now
        )
        apply(model: model, to: &record, now: now)
        try record.insert(db)
        return record.id!
    }

    /// Upserts the person row using the richer `PersonView`, which carries
    /// `is_admin` and aggregates that the bare `Person` does not.
    static func upsertPerson(
        from model: Lemmy.PersonView,
        siteId: Int64,
        in db: Database
    ) throws -> Int64 {
        let id = try upsertPerson(from: model.person, siteId: siteId, in: db)
        if var record = try PersonRecord.fetchOne(db, key: id) {
            record.isAdmin = model.isAdmin
            record.isBanned = model.isBanned
            // v3 keeps the person's post/comment counts on the composed
            // `PersonView` (from `PersonAggregates`), so `PersonView.postCount`/
            // `commentCount` carry them there and the bare `Person`'s own counts
            // are 0; v4 flattens them onto the bare `Person` and leaves the view's
            // nil. Prefer the view-level count, falling back to the person's own.
            record.numberOfPosts = model.postCount ?? model.person.postCount
            record.numberOfComments = model.commentCount ?? model.person.commentCount
            try record.update(db)
        }
        return id
    }

    private static func apply(
        model: Lemmy.Person,
        to record: inout PersonRecord,
        now: Date
    ) {
        record.name = model.name
        record.displayName = model.displayName
        record.avatarUrl = model.avatarUrl
        record.bannerUrl = model.bannerUrl
        record.bio = model.bio
        record.actorId = model.apId
        record.matrixUserId = model.matrixUserId
        // is_admin is only available via PersonView. Default to false here.
        record.isAdmin = false
        // The neutral bare `Person` carries no ban standing (v4 moved `banned`/
        // `ban_expires_at` onto `PersonView`), so `isBanned`/`banExpires` are left
        // as-is here: preserved on an update, defaulted on a fresh insert. The
        // `PersonView` upsert sets `isBanned` authoritatively.
        record.isBotAccount = model.botAccount
        record.isDeleted = model.deleted
        record.isLocal = model.local
        record.personCreatedDate = model.publishedAt
        record.personUpdatedDate = model.updatedAt
        record.updatedAt = now
    }
}
