//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

/// Verifies `PostImporter` mirrors the `PostView`'s per-post creator context
/// (`creator_is_moderator` / `creator_is_admin` / `creator_banned_from_community`)
/// onto the post row, and that a later re-import (a feed/getPost refresh) keeps
/// them current rather than dropping them.
struct PostCreatorContextImportTests {
    private func seedAccount(_ appDatabase: AppDatabase) async throws -> (accountId: Int64, siteId: Int64) {
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: "keychain-creator-context-import",
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return (account.id!, site.id!)
        }
    }

    @Test
    func upsertPost_storesCreatorContextFromPostView() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccount(appDatabase)

        let person = Lemmy.Person.fake
        let community = Lemmy.Community.fake
        let post = Lemmy.Post.fake(creator: person, community: community)
        let view = Lemmy.PostView.fake(
            post: post,
            creator: person,
            community: community,
            creatorBannedFromCommunity: true,
            creatorIsModerator: true,
            creatorIsAdmin: true
        )

        let rowId = try await appDatabase.writer.write { db in
            try AppDatabase.upsertPost(from: view, accountId: accountId, siteId: siteId, in: db)
        }

        let record = try await appDatabase.writer.read { db in
            try PostRecord.filter(key: rowId).fetchOne(db)
        }
        #expect(record?.isCreatorModerator == true)
        #expect(record?.isCreatorAdmin == true)
        #expect(record?.isCreatorBannedFromCommunity == true)
    }

    @Test
    func upsertPost_reimportPreservesCreatorContext() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccount(appDatabase)

        let person = Lemmy.Person.fake
        let community = Lemmy.Community.fake
        let post = Lemmy.Post.fake(creator: person, community: community)
        let view = Lemmy.PostView.fake(
            post: post,
            creator: person,
            community: community,
            creatorBannedFromCommunity: true,
            creatorIsModerator: true,
            creatorIsAdmin: true
        )

        // First import.
        let rowId = try await appDatabase.writer.write { db in
            try AppDatabase.upsertPost(from: view, accountId: accountId, siteId: siteId, in: db)
        }
        // A later feed/getPost refresh re-imports the same PostView.
        let reimportedRowId = try await appDatabase.writer.write { db in
            try AppDatabase.upsertPost(from: view, accountId: accountId, siteId: siteId, in: db)
        }
        #expect(reimportedRowId == rowId, "re-import should update the same row")

        let record = try await appDatabase.writer.read { db in
            try PostRecord.filter(key: rowId).fetchOne(db)
        }
        #expect(record?.isCreatorModerator == true)
        #expect(record?.isCreatorAdmin == true)
        #expect(record?.isCreatorBannedFromCommunity == true)
    }
}
