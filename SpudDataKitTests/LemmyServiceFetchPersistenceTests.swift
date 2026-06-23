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
import XCTest
@testable import SpudDataKit

// MARK: - Type aliases

private typealias Person = Components.Schemas.Person
private typealias PersonView = Components.Schemas.PersonView
private typealias Community = Components.Schemas.Community
private typealias PostView = Components.Schemas.PostView
private typealias CommentView = Components.Schemas.CommentView
private typealias GetPostResponse = Components.Schemas.GetPostResponse
private typealias GetPersonDetailsResponse = Components.Schemas.GetPersonDetailsResponse
private typealias GetCommentsResponse = Components.Schemas.GetCommentsResponse

// MARK: - Stub transports

/// Stub transport returning a canned `GetPostResponse` for the `getPost` operation.
private final class StubGetPostTransport: ClientTransport, @unchecked Sendable {
    private let responseJSON: Data

    init(response: GetPostResponse) throws {
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
        case "getPost":
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

/// Stub transport returning a canned `GetPersonDetailsResponse` for the
/// `getPersonDetails` operation.
private final class StubGetPersonDetailsTransport: ClientTransport, @unchecked Sendable {
    private let responseJSON: Data

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

/// Stub transport returning a canned `GetCommentsResponse` for the
/// `getComments` operation.
private final class StubGetCommentsTransport: ClientTransport, @unchecked Sendable {
    private let responseJSON: Data

    init(response: GetCommentsResponse) throws {
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
        case "getComments":
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

// MARK: - Test class

/// Covers the "persistence-or-throw" contract for fetchPostInfo, fetchPersonInfo,
/// and fetchComments: each must throw when the mirror cannot persist the row,
/// rather than silently returning success and leaving the loading spinner stuck.
@MainActor
final class LemmyServiceFetchPersistenceTests: XCTestCase {
    private let keychainId = "keychain-1"
    private let instanceActorId = "https://example.com"

    private var appDatabase: AppDatabase!

    override func setUpWithError() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    override func tearDown() {
        appDatabase = nil
    }

    // MARK: - Seed helpers

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

    // MARK: - Factory helpers

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

    private func makeGetPostResponse() -> GetPostResponse {
        let person = Person.fake
        let community = Community.fake
        let post = Components.Schemas.Post.fake(creator: person, community: community)
        let postView = PostView.fake(post: post, creator: person, community: community)
        return GetPostResponse(
            post_view: postView,
            community_view: .fake(community: community),
            moderators: [],
            cross_posts: []
        )
    }

    private func makeGetPersonDetailsResponse() -> GetPersonDetailsResponse {
        let person = Person.fake
        return GetPersonDetailsResponse(
            person_view: .fake(person: person),
            site: nil,
            comments: [],
            posts: [],
            moderates: []
        )
    }

    private func makeGetCommentsResponse() -> GetCommentsResponse {
        let person = Person.fake
        let community = Community.fake
        let post = Components.Schemas.Post.fake(creator: person, community: community)
        let comment = Components.Schemas.Comment.fake(
            id: 42,
            post: post,
            creator: person,
            parent: .root
        )
        let commentView = CommentView.fake(
            comment: comment,
            creator: person,
            post: post,
            community: community,
            childCount: 0
        )
        return GetCommentsResponse(comments: [commentView])
    }

    // MARK: - fetchPostInfo tests

    /// Without account/site seeded, mirrorPostInfoToAppDatabase swallows the
    /// failure and no post row appears. fetchPostInfo must detect this and throw
    /// rather than returning success with a missing row.
    func testFetchPostInfoThrowsWhenNotPersisted() async throws {
        // Do NOT seed account/site - the mirror will silently no-op.
        let response = makeGetPostResponse()
        let serverPostId = response.post_view.post.id

        let transport = try StubGetPostTransport(response: response)
        let service = makeService(transport: transport)

        do {
            try await service.fetchPostInfo(serverPostId: serverPostId)
            XCTFail("fetchPostInfo should throw when the post row was not persisted")
        } catch {
            // Expected - any throw is acceptable here.
        }

        // The row must not exist.
        let rowId = appDatabase.postRowIdSync(
            forKeychainId: keychainId,
            serverPostId: Int64(serverPostId)
        )
        XCTAssertNil(rowId, "post row must not exist when persistence failed")
    }

    /// Regression: when account/site IS seeded the mirror succeeds and
    /// fetchPostInfo must NOT throw.
    func testFetchPostInfoSucceedsWhenSeeded() async throws {
        try await seedAccountAndSite()

        let response = makeGetPostResponse()
        let serverPostId = response.post_view.post.id

        let transport = try StubGetPostTransport(response: response)
        let service = makeService(transport: transport)

        do {
            try await service.fetchPostInfo(serverPostId: serverPostId)
        } catch {
            XCTFail("fetchPostInfo should not throw when seeded, but got: \(error)")
        }

        let rowId = appDatabase.postRowIdSync(
            forKeychainId: keychainId,
            serverPostId: Int64(serverPostId)
        )
        XCTAssertNotNil(rowId, "post row must exist after a successful fetch")
    }

    // MARK: - fetchPersonInfo tests

    /// Without account/site seeded, mirrorPersonInfoToAppDatabase swallows the
    /// failure and no person row appears. fetchPersonInfo must detect this and throw.
    func testFetchPersonInfoThrowsWhenNotPersisted() async throws {
        // Do NOT seed account/site.
        let response = makeGetPersonDetailsResponse()
        let serverPersonId = response.person_view.person.id

        let transport = try StubGetPersonDetailsTransport(response: response)
        let service = makeService(transport: transport)

        do {
            try await service.fetchPersonInfo(serverPersonId: serverPersonId)
            XCTFail("fetchPersonInfo should throw when the person row was not persisted")
        } catch {
            // Expected.
        }

        let rowId = appDatabase.personRowIdSync(
            forKeychainId: keychainId,
            personId: Int64(serverPersonId)
        )
        XCTAssertNil(rowId, "person row must not exist when persistence failed")
    }

    /// Regression: when account/site IS seeded the mirror succeeds and
    /// fetchPersonInfo must NOT throw.
    func testFetchPersonInfoSucceedsWhenSeeded() async throws {
        try await seedAccountAndSite()

        let response = makeGetPersonDetailsResponse()
        let serverPersonId = response.person_view.person.id

        let transport = try StubGetPersonDetailsTransport(response: response)
        let service = makeService(transport: transport)

        do {
            try await service.fetchPersonInfo(serverPersonId: serverPersonId)
        } catch {
            XCTFail("fetchPersonInfo should not throw when seeded, but got: \(error)")
        }

        let rowId = appDatabase.personRowIdSync(
            forKeychainId: keychainId,
            personId: Int64(serverPersonId)
        )
        XCTAssertNotNil(rowId, "person row must exist after a successful fetch")
    }

    // MARK: - fetchComments tests

    /// Without account/site seeded, mirrorCommentsToAppDatabase has no account/site
    /// ids to resolve, so it throws (after the fix). fetchComments must propagate
    /// this throw rather than swallowing it.
    func testFetchCommentsThrowsWhenNotPersisted() async throws {
        // Do NOT seed account/site.
        let serverPostId: Components.Schemas.PostID = 1
        let response = makeGetCommentsResponse()

        let transport = try StubGetCommentsTransport(response: response)
        let service = makeService(transport: transport)

        do {
            try await service.fetchComments(
                serverPostId: serverPostId,
                sortType: .Hot
            )
            XCTFail("fetchComments should throw when comments could not be persisted")
        } catch {
            // Expected.
        }
    }
}
