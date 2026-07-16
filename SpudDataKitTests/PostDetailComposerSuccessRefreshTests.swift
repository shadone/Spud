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

private typealias CommentResponse = Lemmy.CommentResponse

/// Stub `ClientTransport` returning a canned `createComment` response, so the
/// `LemmyComposerPerformer` mirrors a real server-confirmed comment through its
/// normal success path (`upsertComment(from:)`).
private final class StubCreateCommentTransport: ClientTransport, @unchecked Sendable {
    private let responseJSON: Data

    init(commentResponse: CommentResponse) throws {
        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        responseJSON = try encoder.encode(commentResponse)
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard operationID == "createComment" else {
            throw UnexpectedOperation(operationID: operationID)
        }
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(responseJSON))
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

/// A no-op performer whose `perform` returns nil (a comment create), so a
/// `ComposerOutboxService` drain reaches the generic success-emit path without
/// any real network I/O.
private actor NoopCommentPerformer: OutboundContentPerforming {
    func perform(_: OutboundContentRecord) async throws -> Int64? {
        nil
    }
}

private final class FakeReachability: ReachabilityMonitoring, @unchecked Sendable {
    @MainActor var isOnline: Bool = true
    @MainActor var statusStream: AsyncStream<Bool> {
        AsyncStream { $0.finish() }
    }
}

/// Guards the fix for the "posted comment not visible until pull-to-refresh" bug
/// (exposed sharply on a fast PieFed server): a comment created through the
/// composer outbox lands in the `comment` table via the single-comment success
/// mirror (`upsertComment(from:)`), which inserts NO `commentElement` row — so it
/// stays invisible to `observePostDetailComments` (rendered exclusively from
/// `commentElement`) until a full `getComments` rebuilds the elements. The app-
/// layer fix subscribes `PostDetailViewModel` to the account's composer success
/// stream and re-fetches on a `.comment` success for the open post; these tests
/// lock the two data-layer invariants that fix depends on.
struct PostDetailComposerSuccessRefreshTests {
    private let keychainId = "kc-piefed"
    private let serverPostId: Int64 = 1
    private let newCommentServerId: Lemmy.CommentID = 42

    private func seedAccountSiteAndPost(
        _ db: AppDatabase
    ) async throws -> (accountId: Int64, siteId: Int64) {
        let ids = try await db.writer.write { write -> (Int64, Int64) in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(write)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(write)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: keychainId,
                isSignedOutAccountType: false
            )
            try account.insert(write)
            return (account.id!, site.id!)
        }

        let postView = Lemmy.PostView.fake(
            post: .fake(creator: .fake, community: .fake),
            creator: .fake,
            community: .fake
        )
        try await db.upsertPost(from: postView, accountId: ids.0, siteId: ids.1)
        return ids
    }

    /// The first (initial) snapshot the comment observation emits for
    /// `(postRowId, sortType)` — the state the open post-detail would render.
    private func firstCommentSnapshot(
        _ db: AppDatabase,
        postRowId: Int64,
        sortType: Lemmy.CommentSortType
    ) async -> [PostDetailCommentRow] {
        for await rows in db.observePostDetailComments(
            postRowId: postRowId,
            sortType: sortType.rawValue
        ) {
            return rows
        }
        return []
    }

    /// The core root-cause guard: after the REAL comment-create success mirror
    /// (`LemmyComposerPerformer.perform`), the new comment is NOT visible to
    /// `observePostDetailComments`; a `getComments`-style rebuild (`upsertComments`)
    /// — exactly what the fix's re-fetch performs — is what makes it appear.
    @Test
    func commentSuccessMirrorIsInvisibleUntilGetCommentsRebuild() async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountSiteAndPost(db)

        // 1. Drive the real success mirror: perform a comment-create outbound row.
        let response = CommentResponse(
            comment_view: V3.commentView(
                comment: V3.comment(id: newCommentServerId),
                creator: V3.person(),
                post: V3.post(),
                community: V3.community()
            ),
            recipient_ids: []
        )
        let transport = try StubCreateCommentTransport(commentResponse: response)
        let api = try LemmyApi(
            instanceUrl: #require(URL(string: "https://example.com")),
            credential: LemmyCredential(jwt: "fake-jwt"),
            transport: transport
        )
        let performer = LemmyComposerPerformer(
            api: api, appDatabase: db, accountId: accountId, siteId: siteId
        )

        let input = OutboundDraftInput(
            kind: .comment,
            body: "hello from piefed",
            postServerId: serverPostId,
            parentCommentServerId: nil,
            communityServerId: nil,
            title: nil,
            url: nil,
            nsfw: false,
            postType: 0
        )
        let token = try await db.upsertOutboundDraft(input, accountId: accountId, now: 0)
        let record = try #require(try await db.writer.read { read in
            try OutboundContentRecord.filter(Column("clientToken") == token).fetchOne(read)
        })
        _ = try await performer.perform(record)

        // The comment row exists...
        let storedBody = try await db.writer.read { read -> String? in
            try CommentRecord
                .filter(Column("localCommentId") == Int64(newCommentServerId))
                .fetchOne(read)?
                .body
        }
        #expect(storedBody != nil, "the success mirror should upsert the comment row")

        // ...but it is invisible to the post-detail comment observation, because
        // the single-comment mirror inserted no commentElement row. This is the bug.
        let postRowId = try #require(db.postRowIdSync(forKeychainId: keychainId, serverPostId: serverPostId))
        let beforeRebuild = await firstCommentSnapshot(db, postRowId: postRowId, sortType: .Hot)
        #expect(
            beforeRebuild.isEmpty,
            "a comment created via the single-comment success mirror must NOT appear in observePostDetailComments (no commentElement row) — got \(beforeRebuild.count)"
        )

        // 2. A getComments-style rebuild (what the fix's re-fetch runs) inserts the
        // commentElement rows, so the comment becomes visible.
        let neutralPost = Lemmy.Post.fake(creator: .fake, community: .fake)
        let neutralView = Lemmy.CommentView.fake(
            comment: .fake(id: newCommentServerId, post: neutralPost, creator: .fake, parent: .root),
            creator: .fake,
            post: neutralPost,
            community: .fake,
            childCount: 0
        )
        try await db.upsertComments(
            forServerPostId: serverPostId,
            accountId: accountId,
            siteId: siteId,
            sortType: .Hot,
            comments: [neutralView]
        )

        let afterRebuild = await firstCommentSnapshot(db, postRowId: postRowId, sortType: .Hot)
        #expect(
            afterRebuild.contains { $0.serverCommentId == Int64(newCommentServerId) },
            "after a getComments-style rebuild the comment must be visible in observePostDetailComments"
        )
    }

    /// The plumbing the fix filters on: a `.comment` success emitted by the
    /// composer outbox carries the CONTAINING post's server id
    /// (`ComposerOutboxSuccess.postServerId`), so an open post-detail can tell the
    /// success is for ITS post. Fails before the enrichment (the field was absent /
    /// nil for comments), passes after.
    @Test
    func commentSuccessEventCarriesContainingPostId() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try await OutboundContentMigrationTests.seedAccount(db)
        let containingPostId: Int64 = 7

        let service = ComposerOutboxService(
            accountId: accountId,
            appDatabase: db,
            performer: NoopCommentPerformer(),
            reachability: FakeReachability(),
            now: { 0 },
            diagnostics: DiagnosticLogSpy(),
            instance: nil
        )
        let successes = await service.successEvents

        let input = OutboundDraftInput(
            kind: .comment,
            body: "hi",
            postServerId: containingPostId,
            parentCommentServerId: nil,
            communityServerId: nil,
            title: nil,
            url: nil,
            nsfw: false,
            postType: 0
        )
        let token = try await db.upsertOutboundDraft(input, accountId: accountId, now: 0)
        try await db.markOutboundQueued(clientToken: token, now: 0)
        await service.drainOnce()

        var iterator = successes.makeAsyncIterator()
        let event = try #require(await iterator.next())
        #expect(event.clientToken == token)
        #expect(event.kind == .comment)
        #expect(
            event.postServerId == containingPostId,
            "a comment success must carry the containing post id so an open post-detail can re-fetch its tree"
        )
    }
}
