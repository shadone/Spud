//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudUtilKit
import Testing
@testable import SpudDataKit

/// Integration coverage for the post-detail header's creator-host resolution.
///
/// The header attribution renders "by <user>@<host>". The author's `@host` must
/// be the author's *home* instance (the host of `person.actor_id`), not the
/// observing account's instance (`person.siteId` -> site -> instance), which is
/// always the local instance the post was fetched on.
///
/// This seeds a real in-memory database via the production importers: an account
/// on `lemmy.world` observing a post whose creator's home instance is
/// `beehaw.org`. The resolved header row must carry the author's `beehaw.org`
/// home host, never the `lemmy.world` observing host.
struct PostDetailHeaderCreatorHostTests {
    @Test
    func observePostDetailHeader_resolvesCreatorHomeHostNotObservingInstance() async throws {
        let appDatabase = try AppDatabase.inMemory()

        // The observing account lives on lemmy.world. `person.siteId` will point
        // at this site for every person imported through this account.
        let (accountId, siteId) = try await appDatabase.writer.write { db -> (Int64, Int64) in
            var instance = InstanceRecord(actorId: "https://lemmy.world")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: "keychain-creator-host-test",
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return (account.id!, site.id!)
        }

        // The post's creator's home instance is beehaw.org — encoded in their
        // federation actor_id, which differs from the observing lemmy.world site.
        var creator = Lemmy.Person.fake
        creator.actor_id = "https://beehaw.org/u/Tony"
        creator.name = "Tony"

        let community = Lemmy.Community.fake
        let post = Lemmy.Post.fake(creator: creator, community: community)
        let view = Lemmy.PostView.fake(post: post, creator: creator, community: community)

        let rowId = try await appDatabase.writer.write { db in
            try AppDatabase.upsertPost(from: view, accountId: accountId, siteId: siteId, in: db)
        }

        // Pull the first emitted header row from the observation stream.
        var iterator = appDatabase.observePostDetailHeader(postRowId: rowId).makeAsyncIterator()
        let headerRow = try #require(await iterator.next() ?? nil)

        // The creator actor id must be the author's *home* actor URL, whose host
        // is beehaw.org — not the lemmy.world observing instance.
        let creatorHost = try #require(InstanceActorId(from: headerRow.creatorActorId ?? "")?.host)
        #expect(creatorHost == "beehaw.org")
        #expect(creatorHost != "lemmy.world")
    }
}
