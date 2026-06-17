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
}
