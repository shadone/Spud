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

/// The `GetPersonDetailsResponse` payload (person_view + posts + comments) is fed
/// to a stub transport, so it is built on the generated v3 shapes via the `V3`
/// fakes; the neutral endpoint decodes the JSON and maps it to `PersonContentPage`.
private typealias GetPersonDetailsResponse = Lemmy.GetPersonDetailsResponse

/// Stub `ClientTransport` returning a canned `GetPersonDetailsResponse` for the
/// `getPersonDetails` operation, recording whether it was invoked.
private final class StubGetPersonDetailsTransport: ClientTransport, @unchecked Sendable {
    private let responseJSON: Data
    private(set) var didSendGetPersonDetails = false

    init(response: GetPersonDetailsResponse) throws {
        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        responseJSON = try encoder.encode(response)
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch operationID {
        case "getPersonDetails":
            didSendGetPersonDetails = true
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(responseJSON))
        default:
            throw UnexpectedOperation(operationID: operationID)
        }
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

@MainActor
struct LemmyServiceFetchPersonContentTests {
    private let keychainId = "keychain-1"

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    @discardableResult
    private func seedAccountAndSite() async throws -> Int64 {
        let keychainId = keychainId
        return try await appDatabase.writer.write { db -> Int64 in
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
            return account.id!
        }
    }

    /// A generated v3 `PersonView` for the `GetPersonDetailsResponse.person_view`
    /// stub payload; v3 keeps `post_count`/`comment_count` on `PersonAggregates`,
    /// which the neutral mirror folds onto the person row.
    private func personView(id: Lemmy.PersonID, name: String, posts: Int64, comments: Int64) -> Components.Schemas.PersonView {
        V3.personView(person: V3.person(id: id, name: name), postCount: posts, commentCount: comments)
    }

    @Test
    func fetchPersonContentReturnsPostsAndCommentsAndMirrorsProfile() async throws {
        try await seedAccountAndSite()

        let personId: Lemmy.PersonID = 1
        let postId: Lemmy.PostID = 1
        let commentId: Lemmy.CommentID = 11

        // The person's post + comment feed the generated `GetPersonDetailsResponse`,
        // so they are built on the generated v3 shapes; the post/comment creator id
        // matches the person_view id so the later profile mirror overwrites the same
        // (initially bare) person row.
        let post = V3.post(id: postId, creatorId: personId)
        let postView = V3.postView(post: post, creator: V3.person(id: personId), community: V3.community())
        let comment = V3.comment(id: commentId, postId: postId, creatorId: personId)
        let commentView = V3.commentView(
            comment: comment,
            creator: V3.person(id: personId),
            post: post,
            community: V3.community(),
            childCount: 0
        )

        let response = GetPersonDetailsResponse(
            person_view: personView(id: personId, name: "alice", posts: 42, comments: 7),
            site: nil,
            comments: [commentView],
            posts: [postView],
            moderates: []
        )

        let transport = try StubGetPersonDetailsTransport(response: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            transport: transport
        )

        let result = try await service.fetchPersonContent(
            serverPersonId: personId,
            sort: .New,
            page: 1
        )

        #expect(transport.didSendGetPersonDetails, "fetchPersonContent should call getPersonDetails")

        // Transient content is returned directly.
        #expect(result.posts.count == 1)
        #expect(result.posts.first?.post.id == Int64(postId))
        #expect(result.comments.count == 1)
        #expect(result.comments.first?.comment.id == Int64(commentId))

        // The profile (person_view) is mirrored into the database.
        let mirrored = try await appDatabase.writer.read { db -> (String?, Int64, Int64)? in
            guard let row = try Row.fetchOne(db, sql: """
                    SELECT name, numberOfPosts, numberOfComments
                    FROM person
                    WHERE personId = ?
                """, arguments: [Int64(personId)])
            else { return nil }
            return (row["name"], row["numberOfPosts"], row["numberOfComments"])
        }
        #expect(mirrored?.0 == "alice")
        #expect(mirrored?.1 == 42)
        #expect(mirrored?.2 == 7)

        // The posts are persisted as real PostRecords (so the profile's Posts
        // tab can render them with the canonical PostListPostCell). The profile
        // mirror runs AFTER the post import, so the richer person_view name
        // ("alice") still wins over the post's bare creator.
        let persistedPost = try await appDatabase.writer.read { db -> String? in
            try Row.fetchOne(db, sql: """
                    SELECT title FROM post WHERE postId = ?
                """, arguments: [Int64(postId)])?["title"]
        }
        #expect(persistedPost == "Hello world", "the person's post should be persisted")
    }

    @Test
    func fetchPersonContentReturnsEmptyListsWhenNoContent() async throws {
        try await seedAccountAndSite()

        let personId: Lemmy.PersonID = 1
        let response = GetPersonDetailsResponse(
            person_view: personView(id: personId, name: "alice", posts: 0, comments: 0),
            site: nil,
            comments: [],
            posts: [],
            moderates: []
        )

        let transport = try StubGetPersonDetailsTransport(response: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            transport: transport
        )

        let result = try await service.fetchPersonContent(
            serverPersonId: personId,
            sort: .New,
            page: 1
        )

        #expect(transport.didSendGetPersonDetails)
        #expect(result.posts.isEmpty)
        #expect(result.comments.isEmpty)
    }
}
