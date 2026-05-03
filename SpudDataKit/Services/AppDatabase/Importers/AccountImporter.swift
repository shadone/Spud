//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import OSLog

private let logger = Logger.appDatabase

extension AppDatabase {
    /// Upserts an account row tied to `siteId`, optionally including the
    /// signed-in user's person row and per-account settings drawn from the
    /// `MyUserInfo` payload of `GetSiteResponse`.
    @discardableResult
    public func upsertAccount(
        keychainId: String,
        isSignedOut: Bool,
        siteId: Int64,
        myUser: Components.Schemas.MyUserInfo?
    ) async throws -> Int64 {
        try await writer.write { db in
            let now = Date()

            let personId: Int64? = try myUser.flatMap { info in
                try Self.upsertPerson(
                    from: info.local_user_view.person,
                    siteId: siteId,
                    in: db
                )
            }

            let resolvedAccountId: Int64
            if var existing = try AccountRecord
                .filter(Column("accountKeychainId") == keychainId)
                .fetchOne(db)
            {
                existing.siteId = siteId
                existing.personId = personId ?? existing.personId
                existing.isSignedOutAccountType = isSignedOut
                Self.apply(myUser: myUser, to: &existing, now: now)
                try existing.update(db)
                resolvedAccountId = existing.id!
            } else {
                var record = AccountRecord(
                    siteId: siteId,
                    personId: personId,
                    accountKeychainId: keychainId,
                    isSignedOutAccountType: isSignedOut,
                    createdAt: now,
                    updatedAt: now
                )
                Self.apply(myUser: myUser, to: &record, now: now)
                try record.insert(db)
                resolvedAccountId = record.id!
            }

            return resolvedAccountId
        }
    }

    private static func upsertPerson(
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
            Self.apply(model: model, to: &existing, now: now)
            try existing.update(db)
            return existing.id!
        }

        var record = PersonRecord(
            siteId: siteId,
            personId: Int64(model.id),
            createdAt: now,
            updatedAt: now
        )
        Self.apply(model: model, to: &record, now: now)
        try record.insert(db)
        return record.id!
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
        // is_admin is only exposed on PersonView (not Person), so we cannot
        // tell from MyUserInfo whether the current user is an admin. Match
        // the legacy LemmyPersonInfo+import behaviour and default to false.
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

    private static func apply(
        myUser: Components.Schemas.MyUserInfo?,
        to record: inout AccountRecord,
        now: Date
    ) {
        guard let myUser else {
            record.updatedAt = now
            return
        }

        let local = myUser.local_user_view.local_user
        record.localAccountId = Int64(local.id)
        record.email = local.email
        record.emailVerified = local.email_verified
        record.acceptedApplication = local.accepted_application
        record.defaultListingType = local.default_listing_type.rawValue
        record.defaultSortType = local.default_sort_type.rawValue
        record.showAvatars = local.show_avatars
        record.showBotAccounts = local.show_bot_accounts
        record.showNsfw = local.show_nsfw
        record.showReadPosts = local.show_read_posts
        record.showScores = local.show_scores
        record.updatedAt = now
    }
}
