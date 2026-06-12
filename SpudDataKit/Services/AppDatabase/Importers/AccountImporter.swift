//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import OSLog
import SpudUtilKit

private let logger = Logger.appDatabase

public extension AppDatabase {
    /// Idempotently ensures an account row exists for `keychainId`. If the
    /// row is created here, its `isServiceAccount` and `isSignedOutAccountType`
    /// flags are set from the parameters. Existing rows are not modified —
    /// fuller updates flow through `upsertAccount` once a fetch succeeds.
    @discardableResult
    func ensureAccount(
        keychainId: String,
        siteId: Int64,
        isSignedOut: Bool,
        isServiceAccount: Bool
    ) async throws -> Int64 {
        try await writer.write { db in
            if let existing = try AccountRecord
                .filter(Column("accountKeychainId") == keychainId)
                .fetchOne(db)
            {
                return existing.id!
            }

            let now = Date()
            var record = AccountRecord(
                siteId: siteId,
                accountKeychainId: keychainId,
                isServiceAccount: isServiceAccount,
                isSignedOutAccountType: isSignedOut,
                createdAt: now,
                updatedAt: now
            )
            try record.insert(db)
            return record.id!
        }
    }

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

    /// Deletes the account row matching `keychainId`. Returns true if a row was
    /// removed. Synchronous: `AccountService.logout(...)` runs on MainActor in
    /// response to a user tap and prefers to avoid hopping off to await.
    @discardableResult
    func deleteAccountSync(keychainId: String) throws -> Bool {
        try writer.write { db in
            let deleted = try AccountRecord
                .filter(Column("accountKeychainId") == keychainId)
                .deleteAll(db)
            return deleted > 0
        }
    }

    /// Synchronous: returns the keychainId of an account to fall back to after
    /// `excludingKeychainId` is removed - the remaining default if any,
    /// otherwise the first non-service account by id. Nil if no other account
    /// exists.
    func fallbackAccountKeychainIdSync(excludingKeychainId excluded: String) -> String? {
        do {
            return try writer.read { db in
                try AccountRecord
                    .filter(Column("isServiceAccount") == false)
                    .filter(Column("accountKeychainId") != excluded)
                    .order(sql: "isDefault DESC, isSignedOutAccountType ASC, id ASC")
                    .fetchOne(db)?
                    .accountKeychainId
            }
        } catch {
            logger.error("Failed to resolve fallback account: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The signed-in account's own person, resolved from `account.personId`.
    /// Returns the local person row id, the server-side person id, and the home
    /// instance actor id - everything needed to open the account holder's own
    /// Person profile. Nil until the account's `MyUserInfo` (and thus its
    /// person row) has been imported.
    func accountOwnPersonIdsSync(
        forKeychainId keychainId: String
    ) -> (personRowId: Int64, serverPersonId: Int64, instanceActorId: String)? {
        do {
            return try writer.read { db in
                guard let row = try Row.fetchOne(db, sql: """
                        SELECT
                            person.id        AS personRowId,
                            person.personId  AS serverPersonId,
                            instance.actorId AS instanceActorId
                        FROM account
                        JOIN person   ON person.id = account.personId
                        JOIN site     ON site.id = account.siteId
                        JOIN instance ON instance.id = site.instanceId
                        WHERE account.accountKeychainId = ?
                    """, arguments: [keychainId])
                else {
                    return nil
                }
                return (
                    personRowId: row["personRowId"],
                    serverPersonId: row["serverPersonId"],
                    instanceActorId: row["instanceActorId"]
                )
            }
        } catch {
            logger.error("Failed to resolve account own person ids: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Clears `isDefault` on every account row and sets it on the row
    /// matching `keychainId`. No-op if the row hasn't been imported yet.
    func setDefaultAccount(keychainId: String) async throws {
        try await writer.write { db in
            try Self.applyDefaultAccount(keychainId: keychainId, in: db)
        }
    }

    /// Synchronous companion to `setDefaultAccount(keychainId:)`.
    /// `AccountService.setDefaultAccount(forAccountKeychainId:)` runs on
    /// MainActor in response to user taps and avoids hopping off to await.
    func setDefaultAccountSync(keychainId: String) throws {
        try writer.write { db in
            try Self.applyDefaultAccount(keychainId: keychainId, in: db)
        }
    }

    private static func applyDefaultAccount(keychainId: String, in db: Database) throws {
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

    /// Synchronous: returns the keychainId of the signed-out account for
    /// `instance` matching `isServiceAccount`, creating it (and its sibling
    /// site/instance rows) if no row exists yet.
    func ensureSignedOutAccountKeychainId(
        forInstance instance: InstanceActorId,
        isServiceAccount: Bool
    ) throws -> String {
        try writer.write { db in
            let (_, siteId) = try Self.ensureInstanceAndSite(
                forInstance: instance,
                in: db
            )
            if let existing = try AccountRecord
                .filter(Column("siteId") == siteId)
                .filter(Column("isSignedOutAccountType") == true)
                .filter(Column("isServiceAccount") == isServiceAccount)
                .fetchOne(db)
            {
                return existing.accountKeychainId
            }
            let now = Date()
            var record = AccountRecord(
                siteId: siteId,
                accountKeychainId: UUID().uuidString,
                isServiceAccount: isServiceAccount,
                isSignedOutAccountType: true,
                createdAt: now,
                updatedAt: now
            )
            try record.insert(db)
            return record.accountKeychainId
        }
    }

    /// Synchronous: returns the keychainId of the most appropriate account
    /// for `instance` — the default account on that site if any, otherwise
    /// the first signed-out account on that site, creating a signed-out
    /// non-service account if none exists.
    func bestAccountKeychainId(
        forInstance instance: InstanceActorId
    ) throws -> String {
        try writer.write { db in
            let (_, siteId) = try Self.ensureInstanceAndSite(
                forInstance: instance,
                in: db
            )
            if let defaultAcct = try AccountRecord
                .filter(Column("siteId") == siteId)
                .filter(Column("isDefault") == true)
                .fetchOne(db)
            {
                return defaultAcct.accountKeychainId
            }
            if let signedOut = try AccountRecord
                .filter(Column("siteId") == siteId)
                .filter(Column("isSignedOutAccountType") == true)
                .filter(Column("isServiceAccount") == false)
                .fetchOne(db)
            {
                return signedOut.accountKeychainId
            }
            let now = Date()
            var record = AccountRecord(
                siteId: siteId,
                accountKeychainId: UUID().uuidString,
                isServiceAccount: false,
                isSignedOutAccountType: true,
                createdAt: now,
                updatedAt: now
            )
            try record.insert(db)
            return record.accountKeychainId
        }
    }

    /// Inline ensure-site used by sync helpers above. Mirrors the body of
    /// `ensureSite(forInstance:)` so the entire write happens in one
    /// transaction.
    private static func ensureInstanceAndSite(
        forInstance instance: InstanceActorId,
        in db: Database
    ) throws -> (instanceId: Int64, siteId: Int64) {
        let now = Date()
        let normalizedActorId = instance.actorId

        let instanceId: Int64
        if var existing = try InstanceRecord
            .filter(InstanceRecord.Columns.actorId == normalizedActorId)
            .fetchOne(db)
        {
            existing.updatedAt = now
            try existing.update(db)
            instanceId = existing.id!
        } else {
            var record = InstanceRecord(
                actorId: normalizedActorId,
                createdAt: now,
                updatedAt: now
            )
            try record.insert(db)
            instanceId = record.id!
        }

        let siteId: Int64
        if let existing = try SiteRecord
            .filter(Column("instanceId") == instanceId)
            .fetchOne(db)
        {
            siteId = existing.id!
        } else {
            var record = SiteRecord(
                instanceId: instanceId,
                createdAt: now,
                updatedAt: now
            )
            try record.insert(db)
            siteId = record.id!
        }

        return (instanceId, siteId)
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
