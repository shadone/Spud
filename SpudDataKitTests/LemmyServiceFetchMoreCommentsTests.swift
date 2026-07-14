//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import HTTPTypes
import LemmyKit
import OpenAPIRuntime
import Testing
@testable import SpudDataKit

// MARK: - Stub transport

/// Returns a canned, KNOWN-COMPLETE v3 `GetCommentsResponse` (HTTP 200) whose `comments` array
/// holds the parent (server id 10, path "0.10", child_count 0) and one child (server id 20, path
/// "0.10.20", child_count 0) -- the fetched subtree `fetchMoreComments` splices in. Modeled
/// directly on `LemmyServiceContentNotFoundTests`'s `NotFoundTransport`, which returns the error
/// path (HTTP 400) for the same `getComments` operation; this is its success-path twin. Every
/// field below mirrors LemmyKit's own known-decodable fixture
/// (`Tests/LemmyKitTests/Fixtures/getCommentsResponseV3.json`) -- only the ids/paths/content
/// differ -- so the v3 `Components.Schemas.CommentView` required-field set is satisfied by
/// construction (see the SBT-fixture-completeness gotcha in CLAUDE.md).
private final class MoreCommentsTransport: ClientTransport, @unchecked Sendable {
    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let body = Data(Self.responseJSON.utf8)
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(body))
    }

    private static let responseJSON = """
        {
          "comments": [
            {
              "comment": {
                "id": 10,
                "creator_id": 1,
                "post_id": 1,
                "content": "Parent comment",
                "removed": false,
                "published": "2026-06-12T23:39:00.000000Z",
                "deleted": false,
                "ap_id": "https://example.com/comment/10",
                "local": true,
                "path": "0.10",
                "distinguished": false,
                "language_id": 0
              },
              "creator": {
                "id": 1,
                "name": "alice",
                "display_name": "Alice",
                "avatar": "https://example.com/avatar.png",
                "banned": false,
                "published": "2026-06-12T22:09:11.363420Z",
                "actor_id": "https://example.com/u/alice",
                "bio": "Bio",
                "local": true,
                "banner": "https://example.com/banner.png",
                "deleted": false,
                "bot_account": false,
                "instance_id": 1
              },
              "post": {
                "id": 1,
                "name": "Test post",
                "url": "https://example.com/link",
                "creator_id": 1,
                "community_id": 1,
                "removed": false,
                "locked": false,
                "published": "2026-06-12T23:37:46.566375Z",
                "deleted": false,
                "nsfw": false,
                "embed_title": "Example",
                "ap_id": "https://example.com/post/1",
                "local": true,
                "language_id": 0,
                "featured_community": false,
                "featured_local": false,
                "url_content_type": "text/html"
              },
              "community": {
                "id": 1,
                "name": "community",
                "title": "Community",
                "removed": false,
                "published": "2026-06-12T23:37:21.928884Z",
                "deleted": false,
                "nsfw": false,
                "actor_id": "https://example.com/c/community",
                "local": true,
                "hidden": false,
                "posting_restricted_to_mods": false,
                "instance_id": 1,
                "visibility": "Public"
              },
              "counts": {
                "comment_id": 10,
                "score": 1,
                "upvotes": 1,
                "downvotes": 0,
                "published": "2026-06-12T23:39:00.000000Z",
                "child_count": 0
              },
              "creator_banned_from_community": false,
              "banned_from_community": false,
              "creator_is_moderator": false,
              "creator_is_admin": false,
              "subscribed": "NotSubscribed",
              "saved": false,
              "creator_blocked": false
            },
            {
              "comment": {
                "id": 20,
                "creator_id": 1,
                "post_id": 1,
                "content": "Child comment",
                "removed": false,
                "published": "2026-06-12T23:40:00.000000Z",
                "deleted": false,
                "ap_id": "https://example.com/comment/20",
                "local": true,
                "path": "0.10.20",
                "distinguished": false,
                "language_id": 0
              },
              "creator": {
                "id": 1,
                "name": "alice",
                "display_name": "Alice",
                "avatar": "https://example.com/avatar.png",
                "banned": false,
                "published": "2026-06-12T22:09:11.363420Z",
                "actor_id": "https://example.com/u/alice",
                "bio": "Bio",
                "local": true,
                "banner": "https://example.com/banner.png",
                "deleted": false,
                "bot_account": false,
                "instance_id": 1
              },
              "post": {
                "id": 1,
                "name": "Test post",
                "url": "https://example.com/link",
                "creator_id": 1,
                "community_id": 1,
                "removed": false,
                "locked": false,
                "published": "2026-06-12T23:37:46.566375Z",
                "deleted": false,
                "nsfw": false,
                "embed_title": "Example",
                "ap_id": "https://example.com/post/1",
                "local": true,
                "language_id": 0,
                "featured_community": false,
                "featured_local": false,
                "url_content_type": "text/html"
              },
              "community": {
                "id": 1,
                "name": "community",
                "title": "Community",
                "removed": false,
                "published": "2026-06-12T23:37:21.928884Z",
                "deleted": false,
                "nsfw": false,
                "actor_id": "https://example.com/c/community",
                "local": true,
                "hidden": false,
                "posting_restricted_to_mods": false,
                "instance_id": 1,
                "visibility": "Public"
              },
              "counts": {
                "comment_id": 20,
                "score": 1,
                "upvotes": 1,
                "downvotes": 0,
                "published": "2026-06-12T23:40:00.000000Z",
                "child_count": 0
              },
              "creator_banned_from_community": false,
              "banned_from_community": false,
              "creator_is_moderator": false,
              "creator_is_admin": false,
              "subscribed": "NotSubscribed",
              "saved": false,
              "creator_blocked": false
            }
          ]
        }
        """
}

// MARK: - Tests

/// Verifies `LemmyService.fetchMoreComments` wires the paginated subtree fetch to
/// `AppDatabase.spliceMoreComments`: given a stored "load more" placeholder under a parent
/// comment, fetching returns the parent + one child and the placeholder is spliced away. The
/// splice math itself (positions, depths, frontier placeholders) is fully covered by
/// `SpliceMoreCommentsTests` -- this test only proves the service-level fetch -> splice wiring.
@MainActor
struct LemmyServiceFetchMoreCommentsTests {
    @Test
    func fetchMoreComments_splicesFetchedSubtree() async throws {
        let appDatabase = try AppDatabase.inMemory()

        // Seed account/site/post, mirroring SpliceMoreCommentsTests's `seed` helper.
        let (accountId, siteId) = try await appDatabase.writer.write { db -> (Int64, Int64) in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: "keychain-1",
                isSignedOutAccountType: false
            )
            try account.insert(db)
            return (account.id!, site.id!)
        }
        let person = Lemmy.Person.fake
        let community = Lemmy.Community.fake
        let post = Lemmy.Post.fake(creator: person, community: community, id: Lemmy.PostID(1))
        let postRowId = try await appDatabase.upsertPost(
            from: .fake(post: post, creator: person, community: community),
            accountId: accountId,
            siteId: siteId
        )

        // Initial tree: one top-level comment (id 10) that claims 1 missing child, producing a
        // "load more" placeholder whose moreParentId is 10.
        let parent = Lemmy.CommentView.fake(
            comment: .fake(id: 10, post: post, creator: person, parent: .root),
            creator: person, post: post, community: community, childCount: 1
        )
        try await appDatabase.upsertComments(
            forServerPostId: 1, accountId: accountId, siteId: siteId,
            sortType: .Hot, comments: [parent]
        )

        let before = try await appDatabase.writer.read { db in
            try CommentElementRecord
                .filter(Column("postId") == postRowId)
                .filter(Column("sortType") == Lemmy.CommentSortType.Hot.rawValue)
                .order(Column("position"))
                .fetchAll(db)
        }
        #expect(before.count == 2)
        #expect(before[1].commentId == nil)
        #expect(before[1].moreParentId == 10)

        let api = try LemmyApi(
            instanceUrl: #require(URL(string: "https://example.com")),
            credential: LemmyCredential(jwt: "fake-jwt"),
            transport: MoreCommentsTransport()
        )
        let service = LemmyService(
            accountKeychainId: "keychain-1",
            accountIsSignedOut: false,
            appDatabase: appDatabase,
            api: api,
            reachability: StaticReachabilityMonitor(isOnline: true)
        )

        try await service.fetchMoreComments(
            serverPostId: Lemmy.PostID(1),
            parentServerId: 10,
            sortType: .Hot
        )

        let elements = try await appDatabase.writer.read { db in
            try CommentElementRecord
                .filter(Column("postId") == postRowId)
                .filter(Column("sortType") == Lemmy.CommentSortType.Hot.rawValue)
                .order(Column("position"))
                .fetchAll(db)
        }
        #expect(elements.count == 2) // parent + child, placeholder gone
        #expect(elements.allSatisfy { $0.commentId != nil })
    }
}
