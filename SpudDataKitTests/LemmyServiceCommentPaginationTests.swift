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

    /// Maps each stored comment element's SERVER comment id to its element
    /// row id (`.Hot` sort), by joining through the comment row's
    /// `localCommentId`. Lets a test key its identity assertions on the
    /// stable server id rather than on array position (which the walk's
    /// mid-walk imports no longer guarantee, since an additive import may
    /// append a comment out of its final display order until the walk's
    /// closing authoritative import restores it).
    private func elementIdsByServerCommentId(_ appDatabase: AppDatabase, postRowId: Int64) async throws -> [Int64: Int64] {
        try await appDatabase.writer.read { db in
            let elements = try CommentElementRecord
                .filter(Column("postId") == postRowId)
                .filter(Column("sortType") == Lemmy.CommentSortType.Hot.rawValue)
                .fetchAll(db)
            var result: [Int64: Int64] = [:]
            for element in elements {
                guard let commentRowId = element.commentId, let elementId = element.id else { continue }
                guard let comment = try CommentRecord.fetchOne(db, key: commentRowId) else { continue }
                result[comment.localCommentId] = elementId
            }
            return result
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

    /// A second call with a LARGER `maxPages` bound must walk MORE pages than
    /// the first, budget-limited call -- and persist more comments. This is
    /// the mechanism the "Load more comments" affordance depends on
    /// (`PostDetailViewModel.loadMoreCommentPages()`): tapping it re-invokes
    /// `fetchComments` with a bigger bound, and the walk (which always
    /// restarts at page 1 -- see the doc comment on `fetchComments`) must
    /// actually go further, not silently stop at the same `maxCommentPages`
    /// ceiling every time. Every page here advertises a next cursor so
    /// pagination never stops on its own; only the bound does.
    @Test
    func aLargerMaxPagesBoundWalksMorePagesThanTheBaseBudget() async throws {
        let appDatabase = try AppDatabase.inMemory()
        _ = try await seed(appDatabase, serverPostId: 180, accountKeychainId: "kc-comment-pagination-larger-bound")
        let endlessPages = (0..<(LemmyService.maxCommentPages * 3)).map { index in
            SubtreeCommentsFixture.v4Page(
                commentId: Int64(700 + index),
                childCount: 0,
                nextPage: "Pc\(index + 2)"
            )
        }
        let transport = SequencedCommentsTransport(operationID: "GetComments", pages: endlessPages)
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-comment-pagination-larger-bound",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v4
        )

        let firstCompletion = try await service.fetchComments(serverPostId: 180, sortType: .Hot)

        #expect(firstCompletion == .partial(.pageBudgetExhausted))
        let callCountAfterFirst = await transport.callCount
        #expect(callCountAfterFirst == LemmyService.maxCommentPages)
        let storedAfterFirst = try await storedCommentCount(appDatabase)
        #expect(storedAfterFirst == LemmyService.maxCommentPages)

        let secondCompletion = try await service.fetchComments(
            serverPostId: 180,
            sortType: .Hot,
            maxPages: LemmyService.maxCommentPages * 2
        )

        #expect(secondCompletion == .partial(.pageBudgetExhausted))
        // Hoist the await out of #expect: SwiftFormat mangles `#expect(await …)`
        // into invalid syntax (`#expectawait(…)`).
        let callCountAfterSecond = await transport.callCount
        #expect(
            callCountAfterSecond == callCountAfterFirst + LemmyService.maxCommentPages * 2,
            "the larger bound must fetch strictly more pages than the first, budget-limited call"
        )
        let storedAfterSecond = try await storedCommentCount(appDatabase)
        #expect(
            storedAfterSecond > storedAfterFirst,
            "the second, larger-bound call must persist more comments than the first"
        )
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

    /// A second full walk over the SAME multi-page listing must not mint fresh
    /// element ids for comments from later pages. Regression coverage for the
    /// bug where every walk's mid-walk imports pruned with EVERY import
    /// (`AppDatabase.upsertComments` always deleted anything absent from its
    /// given set): the walk's own first import — `comments: firstPage.items`
    /// only — deleted every later page's rows before the rest of the walk
    /// regrew them, so pages 2..N got fresh auto-increment element ids on
    /// EVERY re-walk, silently dropping the reader's collapse state and
    /// scroll position (see `upsertComments(pruningAbsentElements:)`).
    @Test
    func secondWalkPreservesElementIdsOfLaterPages() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let seeded = try await seed(appDatabase, serverPostId: 180, accountKeychainId: "kc-comment-pagination-rewalk")
        // A cycling (not clamping) transport: unlike `SequencedCommentsTransport`,
        // it repeats the same 3-page sequence on a second walk, simulating the
        // SAME static server listing being re-walked -- not an ever-growing one.
        let pages = [
            SubtreeCommentsFixture.v4Page(commentId: 801, childCount: 0, nextPage: "Pc2"),
            SubtreeCommentsFixture.v4Page(commentId: 802, childCount: 0, nextPage: "Pc3"),
            SubtreeCommentsFixture.v4Page(commentId: 803, childCount: 0, nextPage: nil),
        ]
        let transport = CyclingCommentsTransport(operationID: "GetComments", pages: pages)
        let service = LemmyServiceHarness.make(
            accountKeychainId: "kc-comment-pagination-rewalk",
            appDatabase: appDatabase,
            transport: transport,
            apiVersion: .v4
        )

        let firstCompletion = try await service.fetchComments(serverPostId: 180, sortType: .Hot)
        #expect(firstCompletion == .complete)
        let originalElementIds = try await elementIdsByServerCommentId(appDatabase, postRowId: seeded.postRowId)
        #expect(originalElementIds.count == 3)

        let secondCompletion = try await service.fetchComments(serverPostId: 180, sortType: .Hot)
        #expect(secondCompletion == .complete)
        let secondElementIds = try await elementIdsByServerCommentId(appDatabase, postRowId: seeded.postRowId)

        #expect(
            secondElementIds[802] == originalElementIds[802],
            "page 2's comment must keep its element id across a second, full walk"
        )
        #expect(
            secondElementIds[803] == originalElementIds[803],
            "page 3's comment must keep its element id across a second, full walk"
        )
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

/// Serves a fixed page sequence, cycling back to the first page once the
/// sequence is exhausted -- unlike `SequencedCommentsTransport` (which clamps
/// to repeating its LAST page forever), this simulates the SAME static server
/// listing being walked more than once, so a second `fetchComments` call sees
/// the identical pages (and comment ids) the first one did.
private actor CyclingCommentsTransport: ClientTransport {
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
        let index = callCount % pages.count
        callCount += 1
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(pages[index]))
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}
