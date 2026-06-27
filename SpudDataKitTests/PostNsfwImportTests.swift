//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import Testing
@testable import SpudDataKit

struct PostNsfwImportTests {
    @Test
    func upsertPost_persistsNsfwFlagFromPostView() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await appDatabase.writer.write { db -> (Int64, Int64) in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: "keychain-nsfw-test",
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return (account.id!, site.id!)
        }

        let person = Components.Schemas.Person.fake
        let community = Components.Schemas.Community.fake
        let post = Components.Schemas.Post.fake(creator: person, community: community, nsfw: true)
        let view = Components.Schemas.PostView.fake(post: post, creator: person, community: community)

        let rowId = try await appDatabase.writer.write { db in
            try AppDatabase.upsertPost(from: view, accountId: accountId, siteId: siteId, in: db)
        }

        let record = try await appDatabase.writer.read { db in
            try PostRecord.filter(key: rowId).fetchOne(db)
        }
        #expect(record?.isNsfw == true)
    }
}
