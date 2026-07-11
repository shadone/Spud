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
private typealias PostResponse = Lemmy.PostResponse
private typealias CommentResponse = Lemmy.CommentResponse
private typealias BanFromCommunityResponse = Lemmy.BanFromCommunityResponse
private typealias GetSiteResponse = Lemmy.GetSiteResponse
private typealias GetPostResponse = Lemmy.GetPostResponse

/// Stub `ClientTransport` returning canned JSON for the moderation operations,
/// recording which operation was invoked. Mirrors `StubBlockReportTransport`.
private final class StubModerationTransport: ClientTransport, @unchecked Sendable {
    private let removePostJSON: Data?
    private let lockPostJSON: Data?
    private let featurePostJSON: Data?
    private let removeCommentJSON: Data?
    private let distinguishCommentJSON: Data?
    private let banJSON: Data?
    private let getSiteJSON: Data?
    /// `removePost` mirrors its state change by re-fetching through the neutral
    /// getPost (the v3 removePost response can't feed the neutral importer), so a
    /// getPost body is served too.
    private let getPostJSON: Data?

    private(set) var didSendRemovePost = false
    private(set) var didSendLockPost = false
    private(set) var didSendFeaturePost = false
    private(set) var didSendRemoveComment = false
    private(set) var didSendDistinguishComment = false
    private(set) var didSendBan = false
    private(set) var didSendGetSite = false

    init(
        removePost: PostResponse? = nil,
        lockPost: PostResponse? = nil,
        featurePost: PostResponse? = nil,
        removeComment: CommentResponse? = nil,
        distinguishComment: CommentResponse? = nil,
        ban: BanFromCommunityResponse? = nil,
        getSite: GetSiteResponse? = nil,
        getPost: GetPostResponse? = nil
    ) throws {
        let encoder = JSONEncoder()
        // Matches LemmyDateTranscoder: 2024-06-09T11:54:37.981990Z (UTC, 6
        // fractional digits, trailing Z).
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        encoder.dateEncodingStrategy = .formatted(formatter)
        removePostJSON = try removePost.map { try encoder.encode($0) }
        lockPostJSON = try lockPost.map { try encoder.encode($0) }
        featurePostJSON = try featurePost.map { try encoder.encode($0) }
        removeCommentJSON = try removeComment.map { try encoder.encode($0) }
        distinguishCommentJSON = try distinguishComment.map { try encoder.encode($0) }
        banJSON = try ban.map { try encoder.encode($0) }
        getSiteJSON = try getSite.map { try encoder.encode($0) }
        getPostJSON = try getPost.map { try encoder.encode($0) }
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
        case "removePost":
            didSendRemovePost = true
            return try ok(removePostJSON)
        case "lockPost":
            didSendLockPost = true
            return try ok(lockPostJSON)
        case "featurePost":
            didSendFeaturePost = true
            return try ok(featurePostJSON)
        case "removeComment":
            didSendRemoveComment = true
            return try ok(removeCommentJSON)
        case "distinguishComment":
            didSendDistinguishComment = true
            return try ok(distinguishCommentJSON)
        case "banUserFromCommunity":
            didSendBan = true
            return try ok(banJSON)
        case "getSite":
            didSendGetSite = true
            return try ok(getSiteJSON)
        case "getPost":
            return try ok(getPostJSON)
        default:
            throw UnexpectedOperation(operationID: operationID)
        }
    }

    struct UnexpectedOperation: Error {
        let operationID: String
    }
}

@MainActor
struct LemmyServiceModerationTests {
    private let keychainId = "keychain-mod-1"

    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    /// Seeds instance + site + account so the mod mirror can resolve the
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

    /// Seeds a post row (via the importer) so a mod action's mirror updates an
    /// existing row. Returns the seeded post's server id.
    @discardableResult
    private func seedPost(
        accountId: Int64,
        siteId: Int64,
        post: Post,
        creator: Person,
        community: Community
    ) async throws -> Int64 {
        let view = Lemmy.PostView.fake(post: post, creator: creator, community: community)
        try await appDatabase.upsertPost(from: view, accountId: accountId, siteId: siteId)
        return Int64(post.id)
    }

    // MARK: removePost mirrors state

    @Test
    func removePostHitsApiAndMirrorsRemovedFlag() async throws {
        let ids = try await seedAccountAndSite()

        let person = Person.fake
        let community = Community.fake
        let postId: Lemmy.PostID = 1
        // Seed a neutral post (removed defaults false); neutral fields are `let`,
        // so the removed variant is built separately below on the generated v3
        // shapes the stub transport encodes.
        let post = Post.fake(creator: person, community: community, id: postId)
        try await seedPost(accountId: ids.accountId, siteId: ids.siteId, post: post, creator: person, community: community)

        // The server returns the post now flagged removed. `removePost` mirrors the
        // flag by re-fetching through the neutral getPost (the v3 removePost
        // response can't feed the neutral importer), so the removed post_view is
        // served for BOTH the removePost call (decoded then discarded) and the
        // getPost re-fetch that actually drives the mirror.
        var removedView = V3.postView(postId: postId)
        removedView.post.removed = true
        let transport = try StubModerationTransport(
            removePost: PostResponse(post_view: removedView),
            getPost: GetPostResponse(
                post_view: removedView,
                community_view: V3.communityView(),
                moderators: [],
                cross_posts: []
            )
        )
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.removePost(serverPostId: postId, removed: true, reason: "spam")

        #expect(transport.didSendRemovePost, "removePost should call the removePost api")

        let accountId = ids.accountId
        let isRemoved = try await appDatabase.writer.read { db -> Bool? in
            try PostRecord
                .filter(Column("accountId") == accountId)
                .filter(Column("postId") == Int64(postId))
                .fetchOne(db)?
                .isRemoved
        }
        #expect(isRemoved == true, "the removed flag should be mirrored into GRDB")
    }

    @Test
    func removePostSignedOutThrowsAndSkipsApi() async throws {
        try await seedAccountAndSite()

        let transport = try StubModerationTransport(removePost: nil)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        do {
            try await service.removePost(serverPostId: 1, removed: true, reason: nil)
            Issue.record("Expected removePost to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }

        #expect(!(transport.didSendRemovePost), "must not hit the api when signed out")
    }

    // MARK: distinguishComment mirrors state

    //
    // The distinguished-flag mirror was DROPPED in the neutral migration:
    // `distinguishComment` no longer re-fetches the comment (there is no
    // single-comment neutral refetch to re-mirror from, and the v3 response can't
    // feed the neutral importer — see `LemmyService+Moderation`'s comment and the
    // Phase 6 follow-ups), so nothing updates the local `isDistinguished` flag
    // until the next comment-tree load. The test body still builds the confirmed
    // view on the generated v3 shapes so it compiles and can be re-enabled once a
    // re-mirror path returns.

    @Test(.disabled("distinguished-flag mirror dropped in neutral migration (no single-comment refetch); Phase 6 follow-up"))
    func distinguishCommentHitsApiAndMirrorsFlag() async throws {
        let ids = try await seedAccountAndSite()

        let person = Person.fake
        let community = Community.fake
        let post = Post.fake(creator: person, community: community)
        try await seedPost(accountId: ids.accountId, siteId: ids.siteId, post: post, creator: person, community: community)

        let commentId: Lemmy.CommentID = 7
        let comment = Comment.fake(id: commentId, post: post, creator: person, parent: .root)
        // Seed the comment row first (undistinguished; neutral `.distinguished`
        // defaults false and is `let`).
        let seedView = Lemmy.CommentView.fake(
            comment: comment, creator: person, post: post, community: community, childCount: 0
        )
        try await appDatabase.upsertComment(from: seedView, accountId: ids.accountId, siteId: ids.siteId)

        // The server returns the comment now distinguished (built on the generated
        // v3 shapes the stub transport encodes).
        var distinguished = V3.comment(id: commentId)
        distinguished.distinguished = true
        let response = CommentResponse(
            comment_view: V3.commentView(
                comment: distinguished,
                creator: V3.person(),
                post: V3.post(),
                community: V3.community(),
                childCount: 0
            ),
            recipient_ids: []
        )
        let transport = try StubModerationTransport(distinguishComment: response)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        try await service.distinguishComment(serverCommentId: commentId, distinguished: true)

        #expect(transport.didSendDistinguishComment, "distinguishComment should call the api")

        let isDistinguished = try await appDatabase.writer.read { db -> Bool? in
            try CommentRecord
                .filter(Column("localCommentId") == Int64(commentId))
                .fetchOne(db)?
                .isDistinguished
        }
        #expect(isDistinguished == true, "the distinguished flag should be mirrored into GRDB")
    }

    // MARK: banFromCommunity

    @Test
    func banFromCommunitySignedOutThrowsAndSkipsApi() async throws {
        try await seedAccountAndSite()

        let transport = try StubModerationTransport(ban: nil)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        do {
            try await service.banFromCommunity(
                serverCommunityId: 1, serverPersonId: 2, ban: true, removeData: false, reason: nil
            )
            Issue.record("Expected banFromCommunity to throw on a signed-out account")
        } catch LemmyServiceError.requiresAuthentication {
            // Expected.
        }

        #expect(!(transport.didSendBan), "must not hit the api when signed out")
    }

    // MARK: fetchModerationCapability resolves from getSite

    @Test
    func moderationCapabilityResolvesModeratedCommunitiesAndAdmin() async throws {
        try await seedAccountAndSite()

        let getSite = GetSiteResponse.fake(moderates: [42], isAdmin: false)
        let transport = try StubModerationTransport(getSite: getSite)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        let capability = try await service.fetchModerationCapability()

        #expect(transport.didSendGetSite)
        #expect(!(capability.isAdmin))
        #expect(capability.moderatedCommunityIds == [42])
        #expect(capability.canModerate(communityId: 42))
        #expect(!(capability.canModerate(communityId: 99)))
        #expect(capability.hasAnyPower)
    }

    @Test
    func moderationCapabilityAdminCanModerateAnyCommunity() async throws {
        try await seedAccountAndSite()

        let getSite = GetSiteResponse.fake(moderates: [], isAdmin: true)
        let transport = try StubModerationTransport(getSite: getSite)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: false,
            transport: transport
        )

        let capability = try await service.fetchModerationCapability()

        #expect(capability.isAdmin)
        #expect(capability.moderatedCommunityIds.isEmpty)
        // Admins can moderate anywhere.
        #expect(capability.canModerate(communityId: 1))
        #expect(capability.canModerate(communityId: 12345))
        #expect(capability.hasAnyPower)
    }

    @Test
    func moderationCapabilitySignedOutResolvesToNoneWithoutHittingApi() async throws {
        try await seedAccountAndSite()

        let transport = try StubModerationTransport(getSite: nil)
        let service = LemmyServiceHarness.make(
            accountKeychainId: keychainId,
            appDatabase: appDatabase,
            accountIsSignedOut: true,
            transport: transport
        )

        let capability = try await service.fetchModerationCapability()

        #expect(capability == .none)
        #expect(!(capability.hasAnyPower))
        #expect(!(transport.didSendGetSite), "signed-out capability fetch should not hit the api")
    }
}
