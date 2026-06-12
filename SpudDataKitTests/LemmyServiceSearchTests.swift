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

private typealias Person = Components.Schemas.Person
private typealias PersonView = Components.Schemas.PersonView
private typealias PersonAggregates = Components.Schemas.PersonAggregates
private typealias CommunityView = Components.Schemas.CommunityView
private typealias SearchResponse = Components.Schemas.SearchResponse

/// Stub `ClientTransport` that returns a canned `SearchResponse` for the
/// `search` operation and records whether it was invoked.
private final class StubSearchTransport: ClientTransport, @unchecked Sendable {
    private let responseJSON: Data
    private(set) var didSendSearch = false

    init(searchResponse: SearchResponse) throws {
        let encoder = JSONEncoder()
        // Matches LemmyDateTranscoder's expected Lemmy 0.19 date format.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        responseJSON = try encoder.encode(searchResponse)
    }

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch operationID {
        case "search":
            didSendSearch = true
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

final class LemmyServiceSearchTests: XCTestCase {
    private let keychainId = "keychain-1"

    private var appDatabase: AppDatabase!

    override func setUpWithError() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    override func tearDown() {
        appDatabase = nil
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
            api: api
        )
    }

    private func personView(id: Components.Schemas.PersonID, name: String) -> PersonView {
        var person = Person.fake
        person.id = id
        person.name = name
        return PersonView(
            person: person,
            counts: PersonAggregates(person_id: id, post_count: 0, comment_count: 0),
            is_admin: false
        )
    }

    func testSearchReturnsResponseWithDecodedResults() async throws {
        try await seedAccountAndSite()

        let community = CommunityView.fake(community: .fake, subscribed: .NotSubscribed)
        let person = personView(id: 7, name: "alice")
        let response = SearchResponse(
            type_: .All,
            comments: [],
            posts: [],
            communities: [community],
            users: [person]
        )

        let transport = try StubSearchTransport(searchResponse: response)
        let service = makeService(transport: transport)

        let result = try await service.search(
            query: "alice",
            type: .All,
            sort: .TopAll,
            listingType: .All,
            page: 1
        )

        XCTAssertTrue(transport.didSendSearch, "search should call the search api")

        XCTAssertEqual(result.communities?.count, 1)
        XCTAssertEqual(result.communities?.first?.community.id, community.community.id)
        XCTAssertEqual(result.communities?.first?.community.name, "world")

        XCTAssertEqual(result.users.count, 1)
        XCTAssertEqual(result.users.first?.person.id, 7)
        XCTAssertEqual(result.users.first?.person.name, "alice")

        XCTAssertTrue(result.posts.isEmpty)
        XCTAssertTrue(result.comments.isEmpty)
    }

    func testSearchReturnsEmptyResultsWhenNothingMatches() async throws {
        try await seedAccountAndSite()

        let response = SearchResponse(
            type_: .Communities,
            comments: [],
            posts: [],
            communities: [],
            users: []
        )

        let transport = try StubSearchTransport(searchResponse: response)
        let service = makeService(transport: transport)

        let result = try await service.search(
            query: "nothing-here",
            type: .Communities,
            sort: .TopAll,
            listingType: .All,
            page: 1
        )

        XCTAssertTrue(transport.didSendSearch)
        XCTAssertEqual(result.communities?.count, 0)
        XCTAssertTrue(result.users.isEmpty)
        XCTAssertTrue(result.posts.isEmpty)
        XCTAssertTrue(result.comments.isEmpty)
    }
}
