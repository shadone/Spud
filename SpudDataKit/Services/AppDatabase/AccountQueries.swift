//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    /// One-shot synchronous read of the non-service accounts, ordered like
    /// `observeAccountListRows`. Safe off the main thread, for the App Intents
    /// `AccountAppEntity` query (a background process) which cannot touch the
    /// `@MainActor` `AccountService`.
    func accountsSync() -> [AccountListRow] {
        (try? writer.read { db -> [AccountListRow] in
            let rows = try Row.fetchAll(db, sql: """
                    SELECT
                        account.id              AS accountId,
                        account.accountKeychainId AS accountKeychainId,
                        account.isDefault       AS isDefault,
                        account.isSignedOutAccountType AS isSignedOutAccountType,
                        account.email           AS email,
                        account.sessionNeedsReauth AS sessionNeedsReauth,
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
                // Single column reads (never two chained subscripts) to dodge the
                // GRDB double-optional `??` footgun.
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
                    avatarUrl: avatarUrl,
                    sessionNeedsReauth: row["sessionNeedsReauth"]
                )
            }
        }) ?? []
    }
}
