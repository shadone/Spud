//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// Coverage for `v33_postCreatorContext`: the three per-post creator-context
/// columns exist after migration, and a `PostRecord` round-trips them.
struct PostCreatorContextMigrationTests {
    /// After all migrations the three v33 columns exist on the `post` table.
    @Test
    func creatorContextColumnsExistAfterMigration() async throws {
        let db = try AppDatabase.inMemory()
        let columns = try await db.writer.read { db in
            try db.columns(in: "post").map(\.name)
        }
        for column in ["isCreatorModerator", "isCreatorAdmin", "isCreatorBannedFromCommunity"] {
            #expect(columns.contains(column), "missing v33 column \(column)")
        }
    }

    /// A `PostRecord` written with the three creator-context flags set reads them
    /// back intact; a record left at defaults reads all three false (the additive
    /// default-false migration).
    @Test
    func postRoundTripsCreatorContextFlags() async throws {
        let appDatabase = try AppDatabase.inMemory()

        let (accountId, siteId) = try await appDatabase.writer.write { db -> (Int64, Int64) in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: "keychain-creator-context",
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return (account.id!, site.id!)
        }

        let (communityId, creatorId) = try await appDatabase.writer.write { db -> (Int64, Int64) in
            var community = CommunityRecord(accountId: accountId, communityId: 1)
            try community.insert(db)
            var person = PersonRecord(siteId: siteId, personId: 1)
            try person.insert(db)
            return (community.id!, person.id!)
        }

        // Flags set true round-trip as true.
        let flaggedRowId = try await appDatabase.writer.write { db -> Int64 in
            var post = PostRecord(
                accountId: accountId,
                communityId: communityId,
                creatorId: creatorId,
                postId: 100,
                title: "Flagged",
                originalPostUrl: "https://example.com/post/100",
                isCreatorModerator: true,
                isCreatorAdmin: true,
                isCreatorBannedFromCommunity: true,
                published: Date()
            )
            try post.insert(db)
            return post.id!
        }

        // Defaults read false.
        let defaultRowId = try await appDatabase.writer.write { db -> Int64 in
            var post = PostRecord(
                accountId: accountId,
                communityId: communityId,
                creatorId: creatorId,
                postId: 101,
                title: "Default",
                originalPostUrl: "https://example.com/post/101",
                published: Date()
            )
            try post.insert(db)
            return post.id!
        }

        let (flagged, defaulted) = try await appDatabase.writer.read { db in
            try (
                PostRecord.filter(key: flaggedRowId).fetchOne(db),
                PostRecord.filter(key: defaultRowId).fetchOne(db)
            )
        }

        #expect(flagged?.isCreatorModerator == true)
        #expect(flagged?.isCreatorAdmin == true)
        #expect(flagged?.isCreatorBannedFromCommunity == true)

        #expect(defaulted?.isCreatorModerator == false)
        #expect(defaulted?.isCreatorAdmin == false)
        #expect(defaulted?.isCreatorBannedFromCommunity == false)
    }
}
