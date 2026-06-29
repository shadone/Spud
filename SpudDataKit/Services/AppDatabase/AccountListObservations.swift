//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.appDatabase

/// Composite snapshot row for the AccountList screen. Joins account, site,
/// instance, and the (optional) signed-in person so the cell can render
/// without further lookups.
public struct AccountListRow: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let accountKeychainId: String
    public let isDefault: Bool
    public let isSignedOutAccountType: Bool
    public let instanceHostname: String
    /// The display-name-first label: `person.displayName` when set, else the raw
    /// `person.name` username. `nil` for signed-out (anonymous) accounts.
    public let nickname: String?
    /// The raw `person.name` username (never the display name), so the UI can
    /// build a true `@username@instance` handle. `nil` for signed-out
    /// (anonymous) accounts, which have no person row.
    public let name: String?
    public let email: String?
    /// The signed-in person's avatar URL, when one is known. `nil` for
    /// signed-out (anonymous) accounts, which have no person row — the UI falls
    /// back to a deterministic hue tile in that case.
    public let avatarUrl: URL?

    public init(
        id: Int64,
        accountKeychainId: String,
        isDefault: Bool,
        isSignedOutAccountType: Bool,
        instanceHostname: String,
        nickname: String?,
        name: String?,
        email: String?,
        avatarUrl: URL?
    ) {
        self.id = id
        self.accountKeychainId = accountKeychainId
        self.isDefault = isDefault
        self.isSignedOutAccountType = isSignedOutAccountType
        self.instanceHostname = instanceHostname
        self.nickname = nickname
        self.name = name
        self.email = email
        self.avatarUrl = avatarUrl
    }
}

public extension AppDatabase {
    /// Stream of AccountList rows, ordered by sign-in state then keychain id,
    /// excluding service accounts. Each row carries everything the cell needs.
    func observeAccountListRows() -> AsyncStream<[AccountListRow]> {
        let observation = ValueObservation
            .tracking { db -> [AccountListRow] in
                let rows = try Row.fetchAll(db, sql: """
                        SELECT
                            account.id              AS accountId,
                            account.accountKeychainId AS accountKeychainId,
                            account.isDefault       AS isDefault,
                            account.isSignedOutAccountType AS isSignedOutAccountType,
                            account.email           AS email,
                            instance.actorId        AS instanceActorId,
                            person.name             AS personName,
                            person.displayName      AS personDisplayName,
                            person.avatarUrl        AS personAvatarUrl
                        FROM account
                        JOIN site     ON site.id = account.siteId
                        JOIN instance ON instance.id = site.instanceId
                        LEFT JOIN person ON person.id = account.personId
                        WHERE account.isServiceAccount = 0
                        ORDER BY account.isSignedOutAccountType ASC,
                                 account.accountKeychainId ASC
                    """)

                return rows.map { row in
                    let actorId: String = row["instanceActorId"]
                    let host = URL(string: actorId)?.host ?? actorId
                    let nickname = row.coalescingString("personDisplayName", "personName")
                    // Single column reads (never two chained subscripts) to avoid
                    // the GRDB double-optional `??` footgun; signed-out accounts
                    // have no person row, so these are NULL -> nil -> hue tile and
                    // an instance-only handle.
                    let name: String? = row["personName"]
                    let avatarUrlString: String? = row["personAvatarUrl"]
                    let avatarUrl = avatarUrlString.flatMap { URL(string: $0) }
                    return AccountListRow(
                        id: row["accountId"],
                        accountKeychainId: row["accountKeychainId"],
                        isDefault: row["isDefault"],
                        isSignedOutAccountType: row["isSignedOutAccountType"],
                        instanceHostname: host,
                        nickname: nickname,
                        name: name,
                        email: row["email"],
                        avatarUrl: avatarUrl
                    )
                }
            }
            .removeDuplicates()

        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("AccountList ValueObservation failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
