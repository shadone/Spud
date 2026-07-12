//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import Testing
@testable import SpudDataKit

/// The post cell reserves an image's aspect ratio ahead of the load (so the row
/// doesn't reflow when the image appears) from the `imageWidth`/`imageHeight`
/// columns on `PostRecord`. This locks in that `upsertPost` populates those
/// columns from the neutral `Post`'s `imageWidth`/`imageHeight`, and that a later
/// dimension-less import can't blank a previously-known size.
@MainActor
struct PostImporterImageDimensionsTests {
    private let keychainId = "keychain-1"

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    private func seedAccountAndSite() async throws -> (accountId: Int64, siteId: Int64) {
        let keychainId = keychainId
        return try await appDatabase.writer.write { db -> (Int64, Int64) in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return (account.id!, site.id!)
        }
    }

    private func storedDimensions(
        accountId: Int64,
        serverPostId: Lemmy.PostID
    ) async throws -> (width: Int?, height: Int?) {
        try await appDatabase.writer.read { db in
            let record = try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == Int64(serverPostId))
                .fetchOne(db)
            return (record?.imageWidth, record?.imageHeight)
        }
    }

    private func postView(
        postId: Lemmy.PostID = 1,
        imageWidth: Int?,
        imageHeight: Int?
    ) -> Lemmy.PostView {
        Lemmy.PostView.fake(
            post: Lemmy.Post.fake(
                creator: .fake,
                community: .fake,
                id: postId,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            ),
            creator: .fake,
            community: .fake
        )
    }

    /// A fresh insert of a PostView carrying image dimensions stores them.
    @Test
    func upsertPostPopulatesImageDimensions() async throws {
        let ids = try await seedAccountAndSite()
        let postId: Lemmy.PostID = 1

        try await appDatabase.upsertPost(
            from: postView(postId: postId, imageWidth: 800, imageHeight: 600),
            accountId: ids.accountId,
            siteId: ids.siteId
        )

        let stored = try await storedDimensions(accountId: ids.accountId, serverPostId: postId)
        #expect(stored.width == 800, "imageWidth must be imported from the neutral post")
        #expect(stored.height == 600, "imageHeight must be imported from the neutral post")
    }

    /// A later import that omits dimensions (a backend not carrying image details)
    /// must not blank a previously-known size back to nil.
    @Test
    func upsertPostPreservesKnownDimensionsAgainstDimensionlessImport() async throws {
        let ids = try await seedAccountAndSite()
        let postId: Lemmy.PostID = 1

        try await appDatabase.upsertPost(
            from: postView(postId: postId, imageWidth: 1024, imageHeight: 512),
            accountId: ids.accountId,
            siteId: ids.siteId
        )

        // A refresh that reports no dimensions must leave the known size intact.
        try await appDatabase.upsertPost(
            from: postView(postId: postId, imageWidth: nil, imageHeight: nil),
            accountId: ids.accountId,
            siteId: ids.siteId
        )

        let stored = try await storedDimensions(accountId: ids.accountId, serverPostId: postId)
        #expect(stored.width == 1024, "a dimension-less refresh must not blank a known imageWidth")
        #expect(stored.height == 512, "a dimension-less refresh must not blank a known imageHeight")
    }
}
