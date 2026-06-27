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

private typealias Person = Components.Schemas.Person
private typealias PersonView = Components.Schemas.PersonView
private typealias PersonAggregates = Components.Schemas.PersonAggregates
private typealias PostView = Components.Schemas.PostView
private typealias CommentView = Components.Schemas.CommentView
private typealias Community = Components.Schemas.Community
private typealias GetPersonDetailsResponse = Components.Schemas.GetPersonDetailsResponse

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

    private func makeService(transport: any ClientTransport) -> LemmyService {
        let api = LemmyApi(
            instanceUrl: URL(string: "https://example.com")!,
            credential: LemmyCredential(jwt: "fake-jwt"),
            transport: transport
        )
        return LemmyService(
            accountKeychainId: keychainId,
            accountIsSignedOut: false,
            appDatabase: appDatabase,
            api: api,
            reachability: StaticReachabilityMonitor(isOnline: true)
        )
    }

    private func personView(id: Components.Schemas.PersonID, name: String, posts: Int64, comments: Int64) -> PersonView {
        var person = Person.fake
        person.id = id
        person.name = name
        person.display_name = "Alice"
        return PersonView(
            person: person,
            counts: PersonAggregates(person_id: id, post_count: posts, comment_count: comments),
            is_admin: false
        )
    }

    @Test
    func fetchPersonContentReturnsPostsAndCommentsAndMirrorsProfile() async throws {
        try await seedAccountAndSite()

        let person = Person.fake
        let community = Community.fake
        let post = Components.Schemas.Post.fake(creator: person, community: community)
        let postView = PostView.fake(post: post, creator: person, community: community)
        let comment = Components.Schemas.Comment.fake(id: 11, post: post, creator: person, parent: .root)
        let commentView = CommentView.fake(
            comment: comment,
            creator: person,
            post: post,
            community: community,
            childCount: 0
        )

        let response = GetPersonDetailsResponse(
            person_view: personView(id: person.id, name: "alice", posts: 42, comments: 7),
            site: nil,
            comments: [commentView],
            posts: [postView],
            moderates: []
        )

        let transport = try StubGetPersonDetailsTransport(response: response)
        let service = makeService(transport: transport)

        let result = try await service.fetchPersonContent(
            serverPersonId: person.id,
            sort: .New,
            page: 1
        )

        #expect(transport.didSendGetPersonDetails, "fetchPersonContent should call getPersonDetails")

        // Transient content is returned directly.
        #expect(result.posts.count == 1)
        #expect(result.posts.first?.post.id == post.id)
        #expect(result.comments.count == 1)
        #expect(result.comments.first?.comment.id == 11)

        // The profile (person_view) is mirrored into the database.
        let mirrored = try await appDatabase.writer.read { db -> (String?, Int64, Int64)? in
            guard let row = try Row.fetchOne(db, sql: """
                    SELECT name, numberOfPosts, numberOfComments
                    FROM person
                    WHERE personId = ?
                """, arguments: [Int64(person.id)])
            else { return nil }
            return (row["name"], row["numberOfPosts"], row["numberOfComments"])
        }
        #expect(mirrored?.0 == "alice")
        #expect(mirrored?.1 == 42)
        #expect(mirrored?.2 == 7)
    }

    @Test
    func fetchPersonContentReturnsEmptyListsWhenNoContent() async throws {
        try await seedAccountAndSite()

        let person = Person.fake
        let response = GetPersonDetailsResponse(
            person_view: personView(id: person.id, name: "alice", posts: 0, comments: 0),
            site: nil,
            comments: [],
            posts: [],
            moderates: []
        )

        let transport = try StubGetPersonDetailsTransport(response: response)
        let service = makeService(transport: transport)

        let result = try await service.fetchPersonContent(
            serverPersonId: person.id,
            sort: .New,
            page: 1
        )

        #expect(transport.didSendGetPersonDetails)
        #expect(result.posts.isEmpty)
        #expect(result.comments.isEmpty)
    }
}
