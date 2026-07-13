//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

public extension AppDatabase {
    /// Sets/clears the re-login flag for the account with `keychainId`. Idempotent.
    /// The `isServiceAccount = 0 AND isSignedOutAccountType = 0` guard makes this a
    /// no-op for accounts that must never carry the flag, rather than an error.
    func setAccountSessionNeedsReauth(keychainId: String, _ needsReauth: Bool) async throws {
        try await writer.write { db in
            try db.execute(sql: """
                UPDATE account
                SET sessionNeedsReauth = ?
                WHERE accountKeychainId = ?
                  AND isServiceAccount = 0
                  AND isSignedOutAccountType = 0
                """, arguments: [needsReauth, keychainId])
        }
    }

    /// Same as above, keyed by the account rowid (the mutation outbox holds an
    /// `accountId`, not a keychain id).
    func setAccountSessionNeedsReauth(accountId: Int64, _ needsReauth: Bool) async throws {
        try await writer.write { db in
            try db.execute(sql: """
                UPDATE account
                SET sessionNeedsReauth = ?
                WHERE id = ?
                  AND isServiceAccount = 0
                  AND isSignedOutAccountType = 0
                """, arguments: [needsReauth, accountId])
        }
    }

    /// One-shot: does ANY real account currently need re-login? Drives the tab dot.
    func accountAnyNeedsReauthSync() -> Bool {
        (try? writer.read { db in
            try Bool.fetchOne(db, sql: """
                SELECT EXISTS(
                    SELECT 1 FROM account
                    WHERE sessionNeedsReauth = 1
                      AND isServiceAccount = 0
                      AND isSignedOutAccountType = 0
                )
                """) ?? false
        }) ?? false
    }

    /// Live "any real account needs re-login" stream for the Account-tab badge.
    func observeAnyAccountNeedsReauth() -> AsyncStream<Bool> {
        let observation = ValueObservation
            .tracking { db -> Bool in
                try Bool.fetchOne(db, sql: """
                    SELECT EXISTS(
                        SELECT 1 FROM account
                        WHERE sessionNeedsReauth = 1
                          AND isServiceAccount = 0
                          AND isSignedOutAccountType = 0
                    )
                    """) ?? false
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("AnyAccountNeedsReauth ValueObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// The signed-in account's own `person.name` (username, never display name),
    /// for pre-filling the re-login form. `nil` for signed-out accounts.
    func accountPersonNameSync(forKeychainId keychainId: String) -> String? {
        try? writer.read { db in
            try String.fetchOne(db, sql: """
                SELECT person.name
                FROM account
                JOIN person ON person.id = account.personId
                WHERE account.accountKeychainId = ?
                """, arguments: [keychainId])
        }
    }

    /// Fetches the full account row for `keychainId` (test + flag-read helper).
    func accountRecordSync(forKeychainId keychainId: String) -> AccountRecord? {
        try? writer.read { db in
            try AccountRecord
                .filter(sql: "accountKeychainId = ?", arguments: [keychainId])
                .fetchOne(db)
        }
    }
}
