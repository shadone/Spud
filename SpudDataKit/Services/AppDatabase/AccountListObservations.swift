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
    public let nickname: String?
    public let email: String?

    public init(
        id: Int64,
        accountKeychainId: String,
        isDefault: Bool,
        isSignedOutAccountType: Bool,
        instanceHostname: String,
        nickname: String?,
        email: String?
    ) {
        self.id = id
        self.accountKeychainId = accountKeychainId
        self.isDefault = isDefault
        self.isSignedOutAccountType = isSignedOutAccountType
        self.instanceHostname = instanceHostname
        self.nickname = nickname
        self.email = email
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
                            person.displayName      AS personDisplayName
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
                    return AccountListRow(
                        id: row["accountId"],
                        accountKeychainId: row["accountKeychainId"],
                        isDefault: row["isDefault"],
                        isSignedOutAccountType: row["isSignedOutAccountType"],
                        instanceHostname: host,
                        nickname: nickname,
                        email: row["email"]
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
