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

/// `fetchComments` must walk the whole comment listing, not just page one.
/// v3 returns its tree in a single cursor-less response, but v4 and PieFed
/// listings paginate -- so fetching one page truncated the tree on those
/// dialects permanently.
@MainActor
struct LemmyServiceCommentPaginationTests {
    /// Seeds a post (via the shared `CommentSeed` helper) under the given
    /// `accountKeychainId` -- each test passes the same string it hands to
    /// `LemmyServiceHarness.make` so the service resolves this seeded account.
    private func seed(
        _ appDatabase: AppDatabase,
        serverPostId: Int64,
        accountKeychainId: String
    ) async throws -> (
        accountId: Int64,
        siteId: Int64,
        postRowId: Int64,
        person: Lemmy.Person,
        community: Lemmy.Community,
        post: Lemmy.Post
    ) {
        try await CommentSeed.seed(appDatabase, serverPostId: serverPostId, accountKeychainId: accountKeychainId)
    }

    /// Number of comment element rows stored for the post, across all sorts.
    private func storedCommentCount(_ appDatabase: AppDatabase) async throws -> Int {
        try await appDatabase.writer.read { db in
            try CommentElementRecord
                .filter(Column("commentId") != nil)
                .fetchCount(db)
        }
    }

    /// A v4 listing spanning three pages is walked to the end.
    @Test
    func v4ListingIsWalkedToCompletion() async throws {
        let appDatabase = try AppDatabase.inMemory()
        _ = try await seed(appDatabase, serverPostId: 180, accountKeychainId: "kc-comment-pagination-v4")
        let transport = SequencedCommentsTransport(
            operationID: "GetComments",
            pages: [
                SubtreeCommentsFixture.v4Page(commentId: 501, childCount: 0, nextPage: "Pc2"),
                SubtreeCommentsFixture.v4Page(commentId: 502, childCount: 0, nextPage: "Pc3"),
                SubtreeCommentsFixture.v4Page(commentId: 503, childCount: 0, nextPage: nil),
            ]
        )
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-comment-pagination-v4",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v4
        )

        let completion = try await service.fetchComments(serverPostId: 180, sortType: .Hot)

        #expect(completion == .complete)
        let callCount = await transport.callCount
        #expect(callCount == 3, "every page of the listing must be fetched")
        // Hoist the await out of #expect: SwiftFormat mangles `#expect(await …)`
        // into invalid syntax (`#expectawait(…)`).
        let stored = try await storedCommentCount(appDatabase)
        #expect(stored == 3, "all three pages' comments must be persisted, not just the last one")
    }

    /// A v3 listing has no cursor, so exactly one request is made and nothing
    /// about the existing behavior changes.
    @Test
    func v3ListingIssuesASingleRequest() async throws {
        let appDatabase = try AppDatabase.inMemory()
        _ = try await seed(appDatabase, serverPostId: 180, accountKeychainId: "kc-comment-pagination-v3")
        let transport = SequencedCommentsTransport(
            operationID: "getComments",
            pages: [SubtreeCommentsFixture.v3Page(commentId: 501, childCount: 0)]
        )
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-comment-pagination-v3",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v3
        )

        let completion = try await service.fetchComments(serverPostId: 180, sortType: .Hot)

        #expect(completion == .complete)
        let callCount = await transport.callCount
        #expect(callCount == 1, "v3 has no comment cursor -- one request only")
    }

    /// Hitting the page budget reports `.partial(.pageBudgetExhausted)` rather
    /// than letting a truncated tree pass for whole. Every page here advertises
    /// another cursor, so without the bound this would loop forever.
    @Test
    func exhaustingThePageBudgetReportsPartial() async throws {
        let appDatabase = try AppDatabase.inMemory()
        _ = try await seed(appDatabase, serverPostId: 180, accountKeychainId: "kc-comment-pagination-budget")
        let endlessPages = (0..<(LemmyService.maxCommentPages + 2)).map { index in
            SubtreeCommentsFixture.v4Page(
                commentId: Int64(600 + index),
                childCount: 0,
                nextPage: "Pc\(index + 2)"
            )
        }
        let transport = SequencedCommentsTransport(operationID: "GetComments", pages: endlessPages)
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-comment-pagination-budget",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v4
        )

        let completion = try await service.fetchComments(serverPostId: 180, sortType: .Hot)

        #expect(completion == .partial(.pageBudgetExhausted))
        let callCount = await transport.callCount
        #expect(callCount == LemmyService.maxCommentPages)
    }

    /// A failure on a later page keeps the pages that already arrived: it must
    /// not throw the whole fetch away, and it must not report `.complete`.
    @Test
    func laterPageFailureKeepsEarlierPages() async throws {
        let appDatabase = try AppDatabase.inMemory()
        _ = try await seed(appDatabase, serverPostId: 180, accountKeychainId: "kc-comment-pagination-fail")
        let transport = FailAfterFirstPageTransport(
            firstPage: SubtreeCommentsFixture.v4Page(commentId: 501, childCount: 0, nextPage: "Pc2")
        )
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-comment-pagination-fail",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v4
        )

        let completion = try await service.fetchComments(serverPostId: 180, sortType: .Hot)

        #expect(completion == .partial(.pageFetchFailed))
        // Hoist the await out of #expect: SwiftFormat mangles `#expect(await …)`
        // into invalid syntax (`#expectawait(…)`).
        let kept = try await storedCommentCount(appDatabase)
        #expect(kept >= 1, "page 1 must survive page 2's failure")
    }

    /// A failure on the FIRST page still throws -- there is nothing to keep, and
    /// the caller needs to drive the inline failed state.
    @Test
    func firstPageFailureThrows() async throws {
        let appDatabase = try AppDatabase.inMemory()
        _ = try await seed(appDatabase, serverPostId: 180, accountKeychainId: "kc-comment-pagination-first-fail")
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-comment-pagination-first-fail",
            appDatabase: appDatabase,
            transport: FailingCommentsTransport(),
            apiVersion: .v4
        )

        await #expect(throws: (any Error).self) {
            _ = try await service.fetchComments(serverPostId: 180, sortType: .Hot)
        }
    }
}

/// Serves one good page (advertising a next cursor) and then fails every
/// subsequent request with HTTP 500 -- the mid-pagination failure case.
private actor FailAfterFirstPageTransport: ClientTransport {
    private let firstPage: Data
    private(set) var callCount = 0

    init(firstPage: Data) {
        self.firstPage = firstPage
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        callCount += 1
        if callCount == 1 {
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(firstPage))
        }
        var response = HTTPResponse(status: .internalServerError)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(Data(#"{"error":"internal_server_error"}"#.utf8)))
    }
}
