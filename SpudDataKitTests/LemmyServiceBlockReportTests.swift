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

private typealias Person = Lemmy.Person
private typealias Community = Lemmy.Community
private typealias Post = Lemmy.Post
private typealias Comment = Lemmy.Comment
private typealias PersonView = Lemmy.PersonView
private typealias CommunityView = Lemmy.CommunityView
private typealias BlockPersonResponse = Lemmy.BlockPersonResponse
private typealias BlockCommunityResponse = Lemmy.BlockCommunityResponse
private typealias PostReportResponse = Lemmy.PostReportResponse
private typealias CommentReportResponse = Lemmy.CommentReportResponse

/// Stub `ClientTransport` returning canned JSON for the block / report
/// operations, recording which operation was invoked.
private final class StubBlockReportTransport: ClientTransport, @unchecked Sendable {
    private let blockPersonJSON: Data?
    private let blockCommunityJSON: Data?
    private let postReportJSON: Data?
    private let commentReportJSON: Data?

    private(set) var didSendBlockPerson = false
    private(set) var didSendBlockCommunity = false
    private(set) var didSendReportPost = false
    private(set) var didSendReportComment = false

    init(
        blockPerson: BlockPersonResponse? = nil,
        blockCommunity: BlockCommunityResponse? = nil,
        postReport: PostReportResponse? = nil,
        commentReport: CommentReportResponse? = nil
    ) throws {
        let encoder = JSONEncoder()
        // Matches LemmyDateTranscoder: 2024-06-09T11:54:37.981990Z (UTC, 6
        // fractional digits, trailing Z).
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        blockPersonJSON = try blockPerson.map { try encoder.encode($0) }
        blockCommunityJSON = try blockCommunity.map { try encoder.encode($0) }
        postReportJSON = try postReport.map { try encoder.encode($0) }
        commentReportJSON = try commentReport.map { try encoder.encode($0) }
    }

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        func ok(_ json: Data?) throws -> (HTTPResponse, HTTPBody?) {
            guard let json else { throw UnexpectedOperation(operationID: operationID) }
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(json))
        }

        switch operationID {
        case "blockPerson":
            didSendBlockPerson = true
            return try ok(blockPersonJSON)
        case "blockCommunity":
            didSendBlockCommunity = true
            return try ok(blockCommunityJSON)
        case "reportPost":
            didSendReportPost = true
            return try ok(postReportJSON)
        case "reportComment":
            didSendReportComment = true
            return try ok(commentReportJSON)
        default:
            throw UnexpectedOperation(operationID: operationID)
        }
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

@MainActor
struct LemmyServiceBlockReportTests {
    private let keychainId = "keychain-1"

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    /// Seeds instance + site + account so the block mirror can resolve the
    /// account/site ids. Returns (accountId, siteId).
    @discardableResult
    private func seedAccountAndSite() async throws -> (accountId: Int64, siteId: Int64) {
        let keychainId = keychainId
        return try await appDatabase.writer.write { db -> (Int64, Int64) in
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
    }

    // MARK: Fakes

    private func postReportResponse() -> PostReportResponse {
        let person = Person.fake
        let community = Community.fake
        let post = Post.fake(creator: person, community: community)
        return PostReportResponse(post_report_view: .init(
            post_report: .init(
                id: 1,
                creator_id: person.id,
                post_id: post.id,
                original_post_name: post.name,
                original_post_url: nil,
                original_post_body: nil,
                reason: "spam",
                resolved: false,
                resolver_id: nil,
                published: Date(timeIntervalSince1970: 1_685_577_784),
                updated: nil
            ),
            post: post,
            community: community,
            creator: person,
            post_creator: person,
            creator_banned_from_community: false,
            creator_is_moderator: false,
            creator_is_admin: false,
            subscribed: .NotSubscribed,
            saved: false,
            read: false,
            hidden: false,
            creator_blocked: false,
            my_vote: nil,
            unread_comments: 0,
            counts: .fake(post: post),
            resolver: nil
        ))
    }

    private func commentReportResponse() -> CommentReportResponse {
        let person = Person.fake
        let community = Community.fake
        let post = Post.fake(creator: person, community: community)
        let comment = Comment.fake(id: 7, post: post, creator: person, parent: .root)
        return CommentReportResponse(comment_report_view: .init(
            comment_report: .init(
                id: 1,
                creator_id: person.id,
                comment_id: comment.id,
                original_comment_text: "rude",
                reason: "harassment",
                resolved: false,
                resolver_id: nil,
                published: Date(timeIntervalSince1970: 1_685_577_784),
                updated: nil
            ),
            comment: comment,
            post: post,
            community: community,
            creator: person,
            comment_creator: person,
            counts: .fake(commentId: comment.id, childCount: 0),
            creator_banned_from_community: false,
            creator_is_moderator: false,
            creator_is_admin: false,
            creator_blocked: false,
            subscribed: .NotSubscribed,
            saved: false,
            my_vote: nil,
            resolver: nil
        ))
    }

    // MARK: setBlocked(person:)

    @Test
    func setBlockedPersonHitsApiAndMirrorsPerson() async throws {
        let ids = try await seedAccountAndSite()

        let person = Person.fake
        let response = BlockPersonResponse(person_view: .fake(person: person), blocked: true)
        let transport = try StubBlockReportTransport(blockPerson: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.setBlocked(serverPersonId: person.id, blocked: true)

        #expect(transport.didSendBlockPerson, "setBlocked(person:) should call the blockPerson api")

        // The returned PersonView is mirrored into the person table.
        let storedPersonId = try await appDatabase.writer.read { db -> Int64? in
            try PersonRecord
                .filter(Column("siteId") == ids.siteId)
                .filter(Column("personId") == Int64(person.id))
                .fetchOne(db)?
                .personId
        }
        #expect(storedPersonId == Int64(person.id))
    }

    @Test
    func setBlockedPersonSignedOutThrowsAndSkipsApi() async throws {
        try await seedAccountAndSite()

        let transport = try StubBlockReportTransport(blockPerson: nil)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        do {
            try await service.setBlocked(serverPersonId: 1, blocked: true)
            Issue.record("Expected setBlocked(person:) to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }

        #expect(!transport.didSendBlockPerson, "must not hit the api when signed out")
    }

    // MARK: setBlocked(community:)

    @Test
    func setBlockedCommunityHitsApiAndMirrorsCommunity() async throws {
        let ids = try await seedAccountAndSite()

        let community = Community.fake
        let response = BlockCommunityResponse(
            community_view: .fake(community: community),
            blocked: true
        )
        let transport = try StubBlockReportTransport(blockCommunity: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.setBlocked(serverCommunityId: community.id, blocked: true)

        #expect(transport.didSendBlockCommunity, "setBlocked(community:) should call the blockCommunity api")

        let storedCommunityId = try await appDatabase.writer.read { db -> Int64? in
            try CommunityRecord
                .filter(Column("accountId") == ids.accountId)
                .filter(Column("communityId") == Int64(community.id))
                .fetchOne(db)?
                .communityId
        }
        #expect(storedCommunityId == Int64(community.id))
    }

    @Test
    func setBlockedCommunitySignedOutThrowsAndSkipsApi() async throws {
        try await seedAccountAndSite()

        let transport = try StubBlockReportTransport(blockCommunity: nil)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        do {
            try await service.setBlocked(serverCommunityId: 1, blocked: true)
            Issue.record("Expected setBlocked(community:) to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }

        #expect(!transport.didSendBlockCommunity, "must not hit the api when signed out")
    }

    // MARK: reportPost

    @Test
    func reportPostHitsApi() async throws {
        try await seedAccountAndSite()

        let transport = try StubBlockReportTransport(postReport: postReportResponse())
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.reportPost(serverPostId: 1, reason: "spam")

        #expect(transport.didSendReportPost, "reportPost should call the reportPost api")
    }

    @Test
    func reportPostSignedOutThrowsAndSkipsApi() async throws {
        try await seedAccountAndSite()

        let transport = try StubBlockReportTransport(postReport: nil)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        do {
            try await service.reportPost(serverPostId: 1, reason: "spam")
            Issue.record("Expected reportPost to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }

        #expect(!transport.didSendReportPost, "must not hit the api when signed out")
    }

    // MARK: reportComment

    @Test
    func reportCommentHitsApi() async throws {
        try await seedAccountAndSite()

        let transport = try StubBlockReportTransport(commentReport: commentReportResponse())
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.reportComment(serverCommentId: 7, reason: "harassment")

        #expect(transport.didSendReportComment, "reportComment should call the reportComment api")
    }

    @Test
    func reportCommentSignedOutThrowsAndSkipsApi() async throws {
        try await seedAccountAndSite()

        let transport = try StubBlockReportTransport(commentReport: nil)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        do {
            try await service.reportComment(serverCommentId: 7, reason: "harassment")
            Issue.record("Expected reportComment to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }

        #expect(!transport.didSendReportComment, "must not hit the api when signed out")
    }
}
