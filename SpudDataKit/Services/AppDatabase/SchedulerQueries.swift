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
    /// Keychain ids of signed-out accounts whose home site has not had its
    /// site info imported yet. Drives SchedulerService's first-fetch path:
    /// `site.name` is nil exactly when `SiteImporter.apply` has never run
    /// for the row.
    func signedOutAccountsAwaitingSiteInfo() async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: """
                    SELECT account.accountKeychainId
                    FROM account
                    JOIN site ON site.id = account.siteId
                    WHERE account.isSignedOutAccountType = 1
                      AND site.name IS NULL
                """)
        }
    }

    /// Instance actor ids of sites that have no associated account yet AND
    /// no imported site info.
    func ownerlessSitesAwaitingInfo() async throws -> [InstanceActorId] {
        let raws = try await writer.read { db in
            try String.fetchAll(db, sql: """
                    SELECT instance.actorId
                    FROM site
                    JOIN instance ON instance.id = site.instanceId
                    WHERE site.name IS NULL
                      AND NOT EXISTS (
                          SELECT 1 FROM account WHERE account.siteId = site.id
                      )
                """)
        }
        return raws.compactMap { raw in
            guard let actorId = InstanceActorId(from: raw) else {
                logger.error("Skipping unparseable instance actor id: \(raw, privacy: .public)")
                return nil
            }
            return actorId
        }
    }

    /// Keychain ids of signed-in accounts that have never had `MyUserInfo`
    /// imported. `localAccountId` is nil until `AccountImporter.apply(myUser:)`
    /// has run, which only happens with a non-nil `myUser` payload.
    func signedInAccountsAwaitingMyUserInfo() async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: """
                    SELECT accountKeychainId
                    FROM account
                    WHERE isSignedOutAccountType = 0
                      AND localAccountId IS NULL
                """)
        }
    }

    /// Keychain ids of signed-in accounts that already have `MyUserInfo`
    /// imported (`localAccountId IS NOT NULL`) and were last updated before
    /// `cutoff`. Drives the daily-refresh tick.
    func signedInAccountsStale(updatedBefore cutoff: Date) async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: """
                    SELECT accountKeychainId
                    FROM account
                    WHERE isSignedOutAccountType = 0
                      AND localAccountId IS NOT NULL
                      AND updatedAt < ?
                """, arguments: [cutoff])
        }
    }
}
