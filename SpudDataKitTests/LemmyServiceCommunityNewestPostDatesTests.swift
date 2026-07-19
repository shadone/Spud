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

// MARK: - Canned posts-listing page

/// Builds a canned v3 `getPosts` JSON response body (`GetPostsResponse`) for the
/// stub transport below - one post per `(id, published)` pair. Field shape is
/// adapted from a known-good real fixture (`SpudUITests/post-list-all-hot.json`'s
/// post entry - a live-captured `PostView` this app already decodes
/// successfully), with only `id`/`published`/`counts.id`/`counts.post_id`/
/// `counts.published` parameterized per post.
private enum CommunityPostsFixture {
    static func page(posts: [(id: Int64, published: String)]) -> Data {
        let postsJSON = posts.map { id, published in
            """
            {
              "post": {
                "id": \(id),
                "name": "Post \(id)",
                "url": "https://example.com/post-\(id)",
                "creator_id": 31989,
                "community_id": 9544,
                "removed": false,
                "locked": false,
                "published": "\(published)",
                "deleted": false,
                "nsfw": false,
                "thumbnail_url": "https://example.com/thumb-\(id).jpeg",
                "ap_id": "https://example.com/post/\(id)",
                "local": false,
                "language_id": 37,
                "featured_community": false,
                "featured_local": false
              },
              "creator": {
                "id": 31989,
                "name": "finibus",
                "display_name": "Nunc Finibus Augue",
                "avatar": "https://example.com/avatar.jpeg",
                "banned": false,
                "published": "2023-06-09T16:51:35.914901",
                "actor_id": "https://example.com/u/finibus",
                "bio": "Phasellus et risus quis orci lacinia bibendum",
                "local": false,
                "banner": "https://example.com/banner.jpeg",
                "deleted": false,
                "admin": false,
                "bot_account": false,
                "instance_id": 1192
              },
              "community": {
                "id": 9544,
                "name": "tincidunt",
                "title": "Tincidunt est id molestie bibendum",
                "description": "Nulla fermentum dui pellentesque lacus ultrices",
                "removed": false,
                "published": "2023-06-12T01:33:44.287172",
                "updated": "2023-08-07T18:55:09.939832",
                "deleted": false,
                "nsfw": false,
                "actor_id": "https://example.com/c/tincidunt",
                "local": false,
                "icon": "https://example.com/icon.jpeg",
                "hidden": false,
                "posting_restricted_to_mods": false,
                "instance_id": 1192,
                "visibility": "Public"
              },
              "creator_banned_from_community": false,
              "counts": {
                "id": \(id),
                "post_id": \(id),
                "comments": 0,
                "score": 0,
                "upvotes": 0,
                "downvotes": 0,
                "published": "\(published)",
                "newest_comment_time_necro": "\(published)",
                "newest_comment_time": "\(published)",
                "featured_community": false,
                "featured_local": false,
                "hot_rank": 0,
                "hot_rank_active": 0,
                "community_id": 9544,
                "creator_id": 31989
              },
              "subscribed": "NotSubscribed",
              "saved": false,
              "read": false,
              "creator_blocked": false,
              "unread_comments": 0,
              "banned_from_community": false,
              "creator_is_moderator": false,
              "creator_is_admin": false,
              "hidden": false
            }
            """
        }.joined(separator: ",\n")
        return Data("{\"posts\": [\(postsJSON)]}".utf8)
    }
}

// MARK: - Stub transports

/// Answers the `getPosts` operation with the canned page below. Fails the test
/// with a clear error if a differently-named operation is requested.
private final class StubGetPostsTransport: ClientTransport, @unchecked Sendable {
    private let body: Data

    init(body: Data) {
        self.body = body
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard operationID == "getPosts" else {
            throw UnexpectedOperation(operationID: operationID)
        }
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(body))
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

/// Fails every request with an HTTP 500 - exercises
/// `fetchCommunityNewestPostDates`'s best-effort-nil contract on a
/// transport-level failure.
private final class FailingGetPostsTransport: ClientTransport, @unchecked Sendable {
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

/// Covers `LemmyService.fetchCommunityNewestPostDates` - the feed-less,
/// one-shot newest-post-dates wrapper the reminder poll's community-follow
/// branch (`SchedulerService.pollActivityRemindersSweep` /
/// `ReminderService.pollDueCommunityFollows`) uses to compare a community's
/// live posts against a follow's watermark.
@MainActor
struct LemmyServiceCommunityNewestPostDatesTests {
    /// Three posts at known, distinct `published` stamps map to the matching
    /// `[Date]`, in the server's returned order.
    @Test
    func mapsPostsPagePublishedDatesInOrder() async throws {
        let appDatabase = try AppDatabase.inMemory()
        // JSON carries 6-digit-fractional stamps (matches the shape already
        // proven to decode via `LemmyServiceSubtreeChildCountTests`'s
        // `SubtreeCommentsFixture`); the expected `Date`s are parsed from the
        // whole-second equivalent (zero fractional seconds = the same instant).
        let jsonStamps = [
            "2026-01-01T00:00:00.000000Z",
            "2026-01-02T00:00:00.000000Z",
            "2026-01-03T00:00:00.000000Z",
        ]
        let expectedStamps = [
            "2026-01-01T00:00:00Z",
            "2026-01-02T00:00:00Z",
            "2026-01-03T00:00:00Z",
        ]
        let body = CommunityPostsFixture.page(posts: [
            (id: 101, published: jsonStamps[0]),
            (id: 102, published: jsonStamps[1]),
            (id: 103, published: jsonStamps[2]),
        ])
        let transport = StubGetPostsTransport(body: body)
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-community-dates-success",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v3
        )

        let result = await service.fetchCommunityNewestPostDates(communityId: 9544, showNsfw: false)

        let formatter = ISO8601DateFormatter()
        let expected = expectedStamps.compactMap(formatter.date(from:))
        #expect(expected.count == 3, "Guard: the expected stamps themselves must parse")
        #expect(result == expected)
    }

    /// A transport-level failure (HTTP 500) returns nil rather than throwing -
    /// `pollDueCommunityFollows` treats a nil fetcher result as "fetch failed"
    /// and bumps `nextCheckAt` without firing.
    @Test
    func transportFailureReturnsNilWithoutThrowing() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let transport = FailingGetPostsTransport()
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-community-dates-error",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v3
        )

        let result = await service.fetchCommunityNewestPostDates(communityId: 9544, showNsfw: false)

        #expect(result == nil)
    }
}
