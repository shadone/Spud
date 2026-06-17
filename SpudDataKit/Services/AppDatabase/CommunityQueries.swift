//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    /// Communities the given account follows, ordered by lowercased name. A
    /// one-shot synchronous read mirroring `observeFollowedCommunities` — used by
    /// the App Intents `CommunityAppEntity` query and Spotlight indexing.
    func followedCommunitiesSync(forAccountId accountId: Int64) -> [CommunityRecord] {
        (try? writer.read { db in
            try CommunityRecord.fetchAll(db, sql: """
                    SELECT community.*
                    FROM community
                    JOIN accountFollowedCommunity AS afc
                        ON afc.communityId = community.id
                    WHERE afc.accountId = ?
                    ORDER BY LOWER(community.name) ASC
                """, arguments: [accountId])
        }) ?? []
    }

    /// Convenience for App Intents code that holds an account keychain id rather
    /// than a row id. Empty when the account is not yet imported.
    func followedCommunitiesSync(forAccountKeychainId keychainId: String) -> [CommunityRecord] {
        guard let accountId = accountRowIdSync(forKeychainId: keychainId) else { return [] }
        return followedCommunitiesSync(forAccountId: accountId)
    }

    /// Followed communities for the default (non-service) account, resolved
    /// entirely from the database. Safe off the main thread, so the App Intents
    /// entity query (a background process) can use it without the `@MainActor`
    /// `AccountService`. Mirrors `AccountService.currentDefaultAccountKeychainId`.
    func followedCommunitiesForDefaultAccountSync() -> [CommunityRecord] {
        let keychainId = (try? writer.read { db -> String? in
            try AccountRecord
                .filter(Column("isServiceAccount") == false)
                .order(sql: "isDefault DESC, id ASC")
                .fetchOne(db)?
                .accountKeychainId
        }) ?? nil
        guard let keychainId else { return [] }
        return followedCommunitiesSync(forAccountKeychainId: keychainId)
    }
}
