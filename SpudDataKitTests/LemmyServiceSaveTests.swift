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
private typealias Community = Components.Schemas.Community
private typealias Post = Components.Schemas.Post
private typealias Comment = Components.Schemas.Comment
private typealias PostView = Components.Schemas.PostView
private typealias CommentView = Components.Schemas.CommentView
private typealias PostResponse = Components.Schemas.PostResponse
private typealias CommentResponse = Components.Schemas.CommentResponse

/// Stub `ClientTransport` that returns canned JSON for the `savePost` /
/// `saveComment` operations and records whether each was invoked.
private final class StubSaveTransport: ClientTransport, @unchecked Sendable {
    private let postResponseJSON: Data?
    private let commentResponseJSON: Data?
    private(set) var didSendSavePost = false
    private(set) var didSendSaveComment = false

    init(
        postResponse: PostResponse? = nil,
        commentResponse: CommentResponse? = nil
    ) throws {
        let encoder = JSONEncoder()
        // The generated client decodes dates via LemmyDateTranscoder, which
        // accepts the Lemmy 0.19 format: 2024-06-09T11:54:37.981990Z (UTC,
        // 6 fractional digits, trailing Z).
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        postResponseJSON = try postResponse.map { try encoder.encode($0) }
        commentResponseJSON = try commentResponse.map { try encoder.encode($0) }
    }

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch operationID {
        case "savePost":
            didSendSavePost = true
            guard let postResponseJSON else { throw UnexpectedOperation(operationID: operationID) }
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(postResponseJSON))

        case "saveComment":
            didSendSaveComment = true
            guard let commentResponseJSON else { throw UnexpectedOperation(operationID: operationID) }
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(commentResponseJSON))

        default:
            throw UnexpectedOperation(operationID: operationID)
        }
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

@MainActor
struct LemmyServiceSaveTests {
    private let keychainId = "keychain-1"
    private let serverPostId: Components.Schemas.PostID = 1

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    /// Seeds account + site + an (unsaved) post so the save mirror can resolve
    /// the account/site ids and find the post row. Returns (accountId, siteId).
    @discardableResult
    private func seedAccountSiteAndPost() async throws -> (accountId: Int64, siteId: Int64) {
        let keychainId = keychainId
        let ids = try await appDatabase.writer.write { db -> (Int64, Int64) in
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

            return (account.id!, site.id!)
        }

        let postView = PostView.fake(
            post: .fake(creator: .fake, community: .fake),
            creator: .fake,
            community: .fake
        )
        _ = try await appDatabase.upsertPost(
            from: postView,
            accountId: ids.0,
            siteId: ids.1
        )

        return (ids.0, ids.1)
    }

    // MARK: Post

    @Test
    func setSavedPostMirrorsSavedFlagIntoDatabase() async throws {
        try await seedAccountSiteAndPost()

        // The confirmed view returned by the server carries saved = true.
        let person = Person.fake
        let community = Community.fake
        let post = Post.fake(creator: person, community: community)
        var savedPostView = PostView.fake(post: post, creator: person, community: community)
        savedPostView.saved = true
        let response = PostResponse(post_view: savedPostView)

        let transport = try StubSaveTransport(postResponse: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.setSaved(serverPostId: serverPostId, saved: true)

        #expect(transport.didSendSavePost, "setSaved should call the savePost api")

        let serverPostId = serverPostId
        let storedIsSaved = try await appDatabase.writer.read { db -> Bool? in
            try PostRecord
                .filter(Column("postId") == Int64(serverPostId))
                .fetchOne(db)?
                .isSaved
        }
        #expect(storedIsSaved == true)
    }

    @Test
    func setSavedPostOnSignedOutAccountThrowsAndSkipsApi() async throws {
        try await seedAccountSiteAndPost()

        let transport = try StubSaveTransport(postResponse: nil)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        do {
            try await service.setSaved(serverPostId: serverPostId, saved: true)
            Issue.record("Expected setSaved to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }

        #expect(
            !(transport.didSendSavePost),
            "setSaved must not hit the api when the account is signed out"
        )
    }

    // MARK: Comment

    @Test
    func setSavedCommentMirrorsSavedFlagIntoDatabase() async throws {
        try await seedAccountSiteAndPost()

        let serverCommentId: Components.Schemas.CommentID = 42
        let person = Person.fake
        let community = Community.fake
        let post = Post.fake(creator: person, community: community)
        let comment = Comment.fake(
            id: serverCommentId,
            post: post,
            creator: person,
            parent: .root
        )
        var savedCommentView = CommentView.fake(
            comment: comment,
            creator: person,
            post: post,
            community: community,
            childCount: 0
        )
        savedCommentView.saved = true
        let response = CommentResponse(comment_view: savedCommentView, recipient_ids: [])

        let transport = try StubSaveTransport(commentResponse: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.setSaved(serverCommentId: serverCommentId, saved: true)

        #expect(transport.didSendSaveComment, "setSaved should call the saveComment api")

        let storedIsSaved = try await appDatabase.writer.read { db -> Bool? in
            try CommentRecord
                .filter(Column("localCommentId") == Int64(serverCommentId))
                .fetchOne(db)?
                .isSaved
        }
        #expect(storedIsSaved == true)
    }

    @Test
    func setSavedCommentOnSignedOutAccountThrowsAndSkipsApi() async throws {
        try await seedAccountSiteAndPost()

        let transport = try StubSaveTransport(commentResponse: nil)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        do {
            try await service.setSaved(serverCommentId: 42, saved: true)
            Issue.record("Expected setSaved to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }

        #expect(
            !(transport.didSendSaveComment),
            "setSaved must not hit the api when the account is signed out"
        )
    }
}
