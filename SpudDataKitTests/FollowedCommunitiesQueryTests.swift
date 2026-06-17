//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import XCTest
@testable import SpudDataKit

final class FollowedCommunitiesQueryTests: XCTestCase {
    func test_followedCommunitiesSync_returnsFollowedOrderedByName() throws {
        let appDatabase = try AppDatabase.inMemory()

        let accountId = try appDatabase.writer.write { db -> Int64 in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: "kc",
                isSignedOutAccountType: false
            )
            try account.insert(db)

            var tech = CommunityRecord(
                accountId: account.id!,
                communityId: 1,
                name: "Technology",
                actorId: "https://lemmy.world/c/technology"
            )
            try tech.insert(db)
            var ask = CommunityRecord(
                accountId: account.id!,
                communityId: 2,
                name: "AskScience",
                actorId: "https://beehaw.org/c/askscience"
            )
            try ask.insert(db)
            // Present but not followed — must be excluded.
            var games = CommunityRecord(
                accountId: account.id!,
                communityId: 3,
                name: "Games",
                actorId: "https://lemmy.world/c/games"
            )
            try games.insert(db)

            try db.execute(
                sql: "INSERT INTO accountFollowedCommunity (accountId, communityId) VALUES (?, ?)",
                arguments: [account.id!, tech.id!]
            )
            try db.execute(
                sql: "INSERT INTO accountFollowedCommunity (accountId, communityId) VALUES (?, ?)",
                arguments: [account.id!, ask.id!]
            )
            return account.id!
        }

        let followed = appDatabase.followedCommunitiesSync(forAccountId: accountId)
        XCTAssertEqual(followed.map(\.name), ["AskScience", "Technology"])
    }
}
