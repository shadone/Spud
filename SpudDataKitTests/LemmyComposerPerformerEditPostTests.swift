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

private typealias PostResponse = Lemmy.PostResponse

/// Decoded shape of the `editPost` request body, so a test can assert the
/// performer forwarded the edited `nsfw` flag onto the wire.
private struct EditPostRequest: Decodable {
    let post_id: Int32
    let nsfw: Bool?
}

/// Stub `ClientTransport` returning a canned `PostResponse` for the `editPost`
/// operation and capturing the request body so the test can verify the `nsfw`
/// value the performer sent.
private final class StubEditPostTransport: ClientTransport, @unchecked Sendable {
    private let responseJSON: Data
    private(set) var editCalls = 0
    private(set) var lastRequest: EditPostRequest?

    init(postResponse: PostResponse) throws {
        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        responseJSON = try encoder.encode(postResponse)
    }

    func send(
        _: HTTPRequest,
        body: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard operationID == "editPost" else {
            throw UnexpectedOperation(operationID: operationID)
        }
        editCalls += 1
        if let body {
            let data = try await Data(collecting: body, upTo: .max)
            lastRequest = try? JSONDecoder().decode(EditPostRequest.self, from: data)
        }
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(responseJSON))
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

/// Performer-level coverage for a post EDIT carrying an NSFW change: the
/// `LemmyComposerPerformer` must forward the outbound row's `nsfw` flag to
/// `editPostNeutral(nsfw:)`, so the server-side flag matches the optimistic
/// local write. Per-test `AppDatabase.inMemory()` isolates state.
struct LemmyComposerPerformerEditPostTests {
    private let editPostServerId: Int64 = 42

    private func seedAccountAndSite(_ db: AppDatabase) async throws -> (accountId: Int64, siteId: Int64) {
        try await db.writer.write { write -> (Int64, Int64) in
            var instance = InstanceRecord(actorId: "https://example.com")
            try instance.insert(write)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(write)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: "kc-edit",
                isSignedOutAccountType: false
            )
            try account.insert(write)
            return (account.id!, site.id!)
        }
    }

    /// Canned `editPost` response carrying the edited post, so the performer's
    /// post-edit upsert has a `post_view` to mirror.
    private func makePostResponse(nsfw: Bool) -> PostResponse {
        var post = V3.post(id: Lemmy.PostID(editPostServerId))
        post.nsfw = nsfw
        let postView = V3.postView(post: post, creator: V3.person(), community: V3.community())
        return PostResponse(post_view: postView)
    }

    /// Builds the persisted edit-post outbound row (carrying `nsfw`) and returns it.
    private func makeEditRecord(
        _ db: AppDatabase,
        accountId: Int64,
        nsfw: Bool
    ) async throws -> OutboundContentRecord {
        let input = OutboundDraftInput(
            kind: .post,
            body: "Edited body",
            postServerId: nil,
            parentCommentServerId: nil,
            communityServerId: 1,
            title: "Edited title",
            url: nil,
            nsfw: nsfw,
            postType: 0,
            editPostServerId: editPostServerId
        )
        let token = try await db.upsertOutboundDraft(input, accountId: accountId, now: 0)
        let record = try await db.writer.read { read in
            try OutboundContentRecord.filter(Column("clientToken") == token).fetchOne(read)
        }
        return try #require(record)
    }

    @Test(arguments: [true, false])
    func editPostForwardsNsfwToApi(nsfw: Bool) async throws {
        let db = try AppDatabase.inMemory()
        let (accountId, siteId) = try await seedAccountAndSite(db)

        let transport = try StubEditPostTransport(postResponse: makePostResponse(nsfw: nsfw))
        let api = try LemmyApi(
            instanceUrl: #require(URL(string: "https://example.com")),
            credential: LemmyCredential(jwt: "fake-jwt"),
            transport: transport
        )
        let performer = LemmyComposerPerformer(
            api: api, appDatabase: db, accountId: accountId, siteId: siteId
        )

        let record = try await makeEditRecord(db, accountId: accountId, nsfw: nsfw)
        _ = try await performer.perform(record)

        #expect(transport.editCalls == 1, "the edit must hit editPost exactly once")
        #expect(
            transport.lastRequest?.nsfw == nsfw,
            "editPost must forward the edited nsfw flag (\(nsfw)), got \(String(describing: transport.lastRequest?.nsfw))"
        )
        #expect(transport.lastRequest?.post_id == Int32(editPostServerId))
    }
}
