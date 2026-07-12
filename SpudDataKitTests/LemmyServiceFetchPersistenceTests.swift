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

// MARK: - Type aliases

// These `Get*Response` payloads are fed to a stub transport, so they are built
// on the generated v3 shapes (`Components.Schemas.*`) via the `V3` fakes; the
// neutral endpoint decodes the encoded JSON and maps to the neutral result.
private typealias GetPostResponse = Lemmy.GetPostResponse
private typealias GetPersonDetailsResponse = Lemmy.GetPersonDetailsResponse
private typealias GetCommentsResponse = Lemmy.GetCommentsResponse

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

// MARK: - Test struct

/// Covers the "persistence-or-throw" contract for fetchPostInfo, fetchPersonInfo,
/// and fetchComments: each must throw when the mirror cannot persist the row,
/// rather than silently returning success and leaving the loading spinner stuck.
@MainActor
struct LemmyServiceFetchPersistenceTests {
    private let keychainId = "keychain-1"
    private let instanceActorId = "https://example.com"

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
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

    private func makeGetPostResponse() -> GetPostResponse {
        GetPostResponse(
            post_view: V3.postView(),
            community_view: V3.communityView(),
            moderators: [],
            cross_posts: []
        )
    }

    private func makeGetPersonDetailsResponse() -> GetPersonDetailsResponse {
        GetPersonDetailsResponse(
            person_view: V3.personView(),
            site: nil,
            comments: [],
            posts: [],
            moderates: []
        )
    }

    private func makeGetCommentsResponse() -> GetCommentsResponse {
        GetCommentsResponse(comments: [
            V3.commentView(
                comment: V3.comment(id: 42),
                creator: V3.person(),
                post: V3.post(),
                community: V3.community(),
                childCount: 0
            ),
        ])
    }

    // MARK: - fetchPostInfo tests

    /// Without account/site seeded, mirrorPostInfoToAppDatabase swallows the
    /// failure and no post row appears. fetchPostInfo must detect this and throw
    /// rather than returning success with a missing row.
    @Test
    func fetchPostInfoThrowsWhenNotPersisted() async throws {
        // Do NOT seed account/site - the mirror will silently no-op.
        let response = makeGetPostResponse()
        let serverPostId = response.post_view.post.id

        let transport = try StubGetPostTransport(response: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            transport: transport
        )

        do {
            try await service.fetchPostInfo(serverPostId: serverPostId)
            Issue.record("fetchPostInfo should throw when the post row was not persisted")
        } catch {
            // Expected - any throw is acceptable here.
        }

        // The row must not exist.
        let rowId = appDatabase.postRowIdSync(
            forKeychainId: keychainId,
            serverPostId: Int64(serverPostId)
        )
        #expect(rowId == nil, "post row must not exist when persistence failed")
    }

    /// Regression: when account/site IS seeded the mirror succeeds and
    /// fetchPostInfo must NOT throw.
    @Test
    func fetchPostInfoSucceedsWhenSeeded() async throws {
        try await seedAccountAndSite()

        let response = makeGetPostResponse()
        let serverPostId = response.post_view.post.id

        let transport = try StubGetPostTransport(response: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            transport: transport
        )

        do {
            try await service.fetchPostInfo(serverPostId: serverPostId)
        } catch {
            Issue.record("fetchPostInfo should not throw when seeded, but got: \(error)")
        }

        let rowId = appDatabase.postRowIdSync(
            forKeychainId: keychainId,
            serverPostId: Int64(serverPostId)
        )
        #expect(rowId != nil, "post row must exist after a successful fetch")
    }

    // MARK: - fetchPersonInfo tests

    /// Without account/site seeded, mirrorPersonInfoToAppDatabase swallows the
    /// failure and no person row appears. fetchPersonInfo must detect this and throw.
    @Test
    func fetchPersonInfoThrowsWhenNotPersisted() async throws {
        // Do NOT seed account/site.
        let response = makeGetPersonDetailsResponse()
        let serverPersonId = response.person_view.person.id

        let transport = try StubGetPersonDetailsTransport(response: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            transport: transport
        )

        do {
            try await service.fetchPersonInfo(serverPersonId: serverPersonId)
            Issue.record("fetchPersonInfo should throw when the person row was not persisted")
        } catch {
            // Expected.
        }

        let rowId = appDatabase.personRowIdSync(
            forKeychainId: keychainId,
            personId: Int64(serverPersonId)
        )
        #expect(rowId == nil, "person row must not exist when persistence failed")
    }

    /// Regression: when account/site IS seeded the mirror succeeds and
    /// fetchPersonInfo must NOT throw.
    @Test
    func fetchPersonInfoSucceedsWhenSeeded() async throws {
        try await seedAccountAndSite()

        let response = makeGetPersonDetailsResponse()
        let serverPersonId = response.person_view.person.id

        let transport = try StubGetPersonDetailsTransport(response: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            transport: transport
        )

        do {
            try await service.fetchPersonInfo(serverPersonId: serverPersonId)
        } catch {
            Issue.record("fetchPersonInfo should not throw when seeded, but got: \(error)")
        }

        let rowId = appDatabase.personRowIdSync(
            forKeychainId: keychainId,
            personId: Int64(serverPersonId)
        )
        #expect(rowId != nil, "person row must exist after a successful fetch")
    }

    // MARK: - fetchComments tests

    /// Without account/site seeded, mirrorCommentsToAppDatabase has no account/site
    /// ids to resolve, so it throws (after the fix). fetchComments must propagate
    /// this throw rather than swallowing it.
    @Test
    func fetchCommentsThrowsWhenNotPersisted() async throws {
        // Do NOT seed account/site.
        let serverPostId: Lemmy.PostID = 1
        let response = makeGetCommentsResponse()

        let transport = try StubGetCommentsTransport(response: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            transport: transport
        )

        do {
            try await service.fetchComments(
                serverPostId: serverPostId,
                sortType: .Hot
            )
            Issue.record("fetchComments should throw when comments could not be persisted")
        } catch {
            // Expected.
        }
    }
}
