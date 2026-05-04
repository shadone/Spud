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
        from view: Components.Schemas.PersonView,
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
        from model: Components.Schemas.Person,
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
        from model: Components.Schemas.PersonView,
        siteId: Int64,
        in db: Database
    ) throws -> Int64 {
        let id = try upsertPerson(from: model.person, siteId: siteId, in: db)
        if var record = try PersonRecord.fetchOne(db, key: id) {
            record.isAdmin = model.is_admin
            record.numberOfPosts = Int64(model.counts.post_count)
            record.numberOfComments = Int64(model.counts.comment_count)
            try record.update(db)
        }
        return id
    }

    private static func apply(
        model: Components.Schemas.Person,
        to record: inout PersonRecord,
        now: Date
    ) {
        record.name = model.name
        record.displayName = model.display_name
        record.avatarUrl = model.avatar
        record.bannerUrl = model.banner
        record.bio = model.bio
        record.actorId = model.actor_id
        record.matrixUserId = model.matrix_user_id
        // is_admin is only available via PersonView. Default to false here.
        record.isAdmin = false
        record.isBanned = model.banned
        record.isBotAccount = model.bot_account
        record.isDeleted = model.deleted
        record.isLocal = model.local
        record.banExpires = model.ban_expires
        record.personCreatedDate = model.published
        record.personUpdatedDate = model.updated
        record.updatedAt = now
    }
}
