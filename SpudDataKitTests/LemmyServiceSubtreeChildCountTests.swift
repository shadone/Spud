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

// MARK: - Canned comment-listing pages

/// Builds canned `getComments` / `GetComments` JSON response bodies for the
/// stub transport below. The v3 and v4 shapes are adapted from LemmyKit's own
/// `GetListNeutralTests` fixtures (`getCommentsResponseV3.json` /
/// `getCommentsResponseV4.json`) - known-good payloads the real generated
/// decoder accepts - with only `id`/`child_count`/`next_page` parameterized
/// per test.
private enum SubtreeCommentsFixture {
    /// A v3 `GetCommentsResponse` with a single comment. v3 has no cursor
    /// pagination at all, so this always maps to a single, complete `Page`.
    static func v3Page(commentId: Int64, childCount: Int64) -> Data {
        let json = """
            {
              "comments": [
                {
                  "comment": {
                    "id": \(commentId),
                    "creator_id": 14,
                    "post_id": 180,
                    "content": "test comment \(commentId)",
                    "removed": false,
                    "published": "2026-06-12T23:39:00.000000Z",
                    "deleted": false,
                    "ap_id": "https://test1.lemmy.ddenis.info/comment/\(commentId)",
                    "local": true,
                    "path": "0.\(commentId)",
                    "distinguished": false,
                    "language_id": 0
                  },
                  "creator": {
                    "id": 14,
                    "name": "seed_mod1",
                    "display_name": "Mod One",
                    "avatar": "https://picsum.photos/seed/seed_mod1/400/400",
                    "banned": false,
                    "published": "2026-06-12T22:09:11.363420Z",
                    "actor_id": "https://test1.lemmy.ddenis.info/u/seed_mod1",
                    "bio": "Community moderator.",
                    "local": true,
                    "banner": "https://picsum.photos/seed/seed_mod1-b/1200/300",
                    "deleted": false,
                    "bot_account": false,
                    "instance_id": 1
                  },
                  "post": {
                    "id": 180,
                    "name": "Live recording (thread 8)",
                    "url": "https://example.com/live",
                    "creator_id": 14,
                    "community_id": 29,
                    "removed": false,
                    "locked": false,
                    "published": "2026-06-12T23:37:46.566375Z",
                    "deleted": false,
                    "nsfw": false,
                    "embed_title": "Example Domain",
                    "ap_id": "https://test1.lemmy.ddenis.info/post/180",
                    "local": true,
                    "language_id": 0,
                    "featured_community": false,
                    "featured_local": false,
                    "url_content_type": "text/html"
                  },
                  "community": {
                    "id": 29,
                    "name": "music",
                    "title": "Music",
                    "removed": false,
                    "published": "2026-06-12T23:37:21.928884Z",
                    "deleted": false,
                    "nsfw": false,
                    "actor_id": "https://test1.lemmy.ddenis.info/c/music",
                    "local": true,
                    "hidden": false,
                    "posting_restricted_to_mods": false,
                    "instance_id": 1,
                    "visibility": "Public"
                  },
                  "counts": {
                    "comment_id": \(commentId),
                    "score": 3,
                    "upvotes": 3,
                    "downvotes": 0,
                    "published": "2026-06-12T23:39:00.000000Z",
                    "child_count": \(childCount)
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
        return Data(json.utf8)
    }

    /// A v4 `GetComments` page (`PagedResponse_CommentView_`) with a single
    /// comment and the given `next_page` cursor (nil renders as JSON `null`,
    /// meaning "no more pages").
    static func v4Page(commentId: Int64, childCount: Int64, nextPage: String?) -> Data {
        let nextPageJSON = nextPage.map { "\"\($0)\"" } ?? "null"
        let json = """
            {
              "items": [
                {
                  "comment": {
                    "id": \(commentId),
                    "creator_id": 14,
                    "post_id": 180,
                    "content": "test comment \(commentId)",
                    "removed": false,
                    "published_at": "2026-06-12T23:39:00.000000Z",
                    "deleted": false,
                    "ap_id": "https://test1.lemmy.ddenis.info/comment/\(commentId)",
                    "local": true,
                    "path": "0.\(commentId)",
                    "distinguished": false,
                    "language_id": 0,
                    "locked": false,
                    "federation_pending": false,
                    "unresolved_report_count": 0,
                    "report_count": 0,
                    "child_count": \(childCount),
                    "downvotes": 0,
                    "upvotes": 3,
                    "score": 3
                  },
                  "creator": {
                    "id": 14,
                    "name": "seed_mod1",
                    "display_name": "Mod One",
                    "avatar": "https://picsum.photos/seed/seed_mod1/400/400",
                    "published_at": "2026-06-12T22:09:11.363420Z",
                    "ap_id": "https://test1.lemmy.ddenis.info/u/seed_mod1",
                    "bio": "Community moderator.",
                    "local": true,
                    "banner": "https://picsum.photos/seed/seed_mod1-b/1200/300",
                    "deleted": false,
                    "bot_account": false,
                    "instance_id": 1,
                    "last_refreshed_at": "2026-06-12T22:09:11.363420Z",
                    "post_count": 0,
                    "comment_count": 0
                  },
                  "post": {
                    "id": 180,
                    "name": "Live recording (thread 8)",
                    "url": "https://example.com/live",
                    "creator_id": 14,
                    "community_id": 29,
                    "removed": false,
                    "locked": false,
                    "published_at": "2026-06-12T23:37:46.566375Z",
                    "deleted": false,
                    "nsfw": false,
                    "embed_title": "Example Domain",
                    "ap_id": "https://test1.lemmy.ddenis.info/post/180",
                    "local": true,
                    "language_id": 0,
                    "featured_community": false,
                    "featured_local": false,
                    "comments": 7,
                    "score": 1,
                    "upvotes": 1,
                    "downvotes": 0,
                    "report_count": 0,
                    "unresolved_report_count": 0,
                    "federation_pending": false
                  },
                  "community": {
                    "id": 29,
                    "name": "music",
                    "title": "Music",
                    "removed": false,
                    "published_at": "2026-06-12T23:37:21.928884Z",
                    "deleted": false,
                    "nsfw": false,
                    "ap_id": "https://test1.lemmy.ddenis.info/c/music",
                    "local": true,
                    "posting_restricted_to_mods": false,
                    "instance_id": 1,
                    "visibility": "public",
                    "last_refreshed_at": "2026-06-12T23:37:21.928884Z",
                    "subscribers": 100,
                    "posts": 50,
                    "comments": 200,
                    "subscribers_local": 0,
                    "users_active_day": 0,
                    "users_active_week": 0,
                    "users_active_month": 0,
                    "users_active_half_year": 0,
                    "report_count": 0,
                    "unresolved_report_count": 0,
                    "local_removed": false
                  },
                  "creator_banned_from_community": false,
                  "creator_is_moderator": false,
                  "creator_banned": false,
                  "can_mod": false,
                  "creator_is_admin": false,
                  "tags": []
                }
              ],
              "next_page": \(nextPageJSON),
              "prev_page": null
            }
            """
        return Data(json.utf8)
    }
}

// MARK: - Stub transports

/// Returns a sequence of canned pages, one per call - the Nth call gets
/// `pages[N]`, and every call past the end repeats the last page (so a test
/// that only cares about a bound on the NUMBER of calls doesn't need one
/// canned page per iteration). Fails the test with a clear error if a
/// differently-named operation is requested.
private actor SequencedCommentsTransport: ClientTransport {
    private let operationID: String
    private let pages: [Data]
    private(set) var callCount = 0

    init(operationID: String, pages: [Data]) {
        self.operationID = operationID
        self.pages = pages
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard operationID == self.operationID else {
            throw UnexpectedOperation(operationID: operationID)
        }
        let index = min(callCount, pages.count - 1)
        callCount += 1
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(pages[index]))
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

/// Fails every request with an HTTP 500 - exercises `fetchSubtreeChildCount`'s
/// best-effort-nil contract on a transport-level failure.
private final class FailingCommentsTransport: ClientTransport, @unchecked Sendable {
    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let body = Data(#"{"error":"internal_server_error"}"#.utf8)
        var response = HTTPResponse(status: .internalServerError)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(body))
    }
}

// MARK: - Tests

/// Covers `LemmyService.fetchSubtreeChildCount` (Fix 2 / "reminders loose
/// ends"): the reminder poll's SUBTREE branch needs a subtree root's live
/// `child_count` even when it sorts past page 1 of a v4 (cursor-paginated)
/// comment listing - unlike `fetchComments`, which only ever requests page 1.
@MainActor
struct LemmyServiceSubtreeChildCountTests {
    /// A single-page v3 response already containing the root comment returns
    /// its `child_count` immediately, with no pagination needed.
    @Test
    func singlePageContainingRootReturnsChildCountImmediately() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let rootCommentServerId: Int64 = 501
        let page = SubtreeCommentsFixture.v3Page(commentId: rootCommentServerId, childCount: 7)
        let transport = SequencedCommentsTransport(operationID: "getComments", pages: [page])
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-subtree-single-page",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v3
        )

        let result = await service.fetchSubtreeChildCount(
            postServerId: 180,
            rootCommentServerId: rootCommentServerId,
            sortType: .Hot
        )

        #expect(result == 7)
        let callCount = await transport.callCount
        #expect(callCount == 1)
    }

    /// A v4 root that sorts onto page 2 is still found: page 1 (no match,
    /// `next_page` set) is followed by page 2 (match, `next_page` nil), and
    /// the result comes from page 2's item - the exact gap `fetchComments`
    /// (page-1-only) would have missed.
    @Test
    func multiPageRootOnSecondPagePaginatesAndReturnsItsChildCount() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let rootCommentServerId: Int64 = 501
        let page1 = SubtreeCommentsFixture.v4Page(commentId: 500, childCount: 1, nextPage: "Pc9")
        let page2 = SubtreeCommentsFixture.v4Page(commentId: rootCommentServerId, childCount: 12, nextPage: nil)
        let transport = SequencedCommentsTransport(operationID: "GetComments", pages: [page1, page2])
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-subtree-multi-page",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v4
        )

        let result = await service.fetchSubtreeChildCount(
            postServerId: 180,
            rootCommentServerId: rootCommentServerId,
            sortType: .Hot
        )

        #expect(result == 12)
        let callCount = await transport.callCount
        #expect(callCount == 2)
    }

    /// A root that never appears keeps paginating only up to
    /// `LemmyService.maxSubtreeChildCountPages` - every page here advertises
    /// another `next_page`, so without the bound this would loop forever.
    /// Proves both the nil result AND that the loop actually stops at the
    /// documented page count.
    @Test
    func rootNeverFoundWithinPageBoundReturnsNil() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let rootCommentServerId: Int64 = 999
        let neverMatchingPage = SubtreeCommentsFixture.v4Page(commentId: 1, childCount: 0, nextPage: "Pc-loop")
        let transport = SequencedCommentsTransport(operationID: "GetComments", pages: [neverMatchingPage])
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-subtree-never-found",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v4
        )

        let result = await service.fetchSubtreeChildCount(
            postServerId: 180,
            rootCommentServerId: rootCommentServerId,
            sortType: .Hot
        )

        #expect(result == nil)
        let callCount = await transport.callCount
        #expect(callCount == LemmyService.maxSubtreeChildCountPages)
    }

    /// A transport-level failure on the very first page returns nil rather
    /// than throwing - `pollDueActivityReminders` treats a nil fetcher result
    /// as "fetch failed" and bumps `nextCheckAt` without firing, exactly like
    /// a thrown `fetchComments` error would.
    @Test
    func transportFailureReturnsNilWithoutThrowing() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let transport = FailingCommentsTransport()
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-subtree-error",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v3
        )

        let result = await service.fetchSubtreeChildCount(
            postServerId: 180,
            rootCommentServerId: 501,
            sortType: .Hot
        )

        #expect(result == nil)
    }
}
