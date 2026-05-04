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

public extension AppDatabase {
    /// Upserts an account row tied to `siteId`, optionally including the
    /// signed-in user's person row and per-account settings drawn from the
    /// `MyUserInfo` payload of `GetSiteResponse`.
    @discardableResult
    func upsertAccount(
        keychainId: String,
        isSignedOut: Bool,
        siteId: Int64,
        myUser: Components.Schemas.MyUserInfo?
    ) async throws -> Int64 {
        try await writer.write { db in
            let now = Date()

            let personId: Int64? = try myUser.flatMap { info in
                try AppDatabase.upsertPerson(
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

    /// Synchronous lookup of the home-instance actor URL for the account
    /// matching `keychainId`. Returns nil if the account hasn't been imported
    /// or the join cannot be resolved.
    func accountInstanceActorIdSync(forKeychainId keychainId: String) -> String? {
        do {
            return try writer.read { db in
                try Row.fetchOne(db, sql: """
                        SELECT instance.actorId AS actorId
                        FROM account
                        JOIN site     ON site.id = account.siteId
                        JOIN instance ON instance.id = site.instanceId
                        WHERE account.accountKeychainId = ?
                    """, arguments: [keychainId])?["actorId"]
            }
        } catch {
            logger.error("Failed to resolve account instance actorId: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Returns the row id of the account row matching `keychainId`, or nil
    /// if not yet imported. Synchronous read intended for one-shot UI bring-up
    /// where blocking the caller briefly is preferable to making `init` async.
    func accountRowIdSync(forKeychainId keychainId: String) -> Int64? {
        do {
            return try writer.read { db in
                try AccountRecord
                    .filter(Column("accountKeychainId") == keychainId)
                    .fetchOne(db)?
                    .id
            }
        } catch {
            logger.error("Failed to resolve account row id: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Mirrors the Core Data "default account" flag: clears `isDefault` on
    /// every row and sets it on the row matching `keychainId`. No-op if the
    /// row hasn't been imported yet.
    func setDefaultAccount(keychainId: String) async throws {
        try await writer.write { db in
            let now = Date()

            try db.execute(sql: """
                    UPDATE account
                    SET isDefault = 0,
                        updatedAt = ?
                    WHERE isDefault = 1
                """, arguments: [now])

            guard var target = try AccountRecord
                .filter(Column("accountKeychainId") == keychainId)
                .fetchOne(db)
            else { return }
            target.isDefault = true
            target.updatedAt = now
            try target.update(db)
        }
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
