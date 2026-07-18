//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
@testable import Spud

/// Minimal `PostDetailHeaderRow` test factory, mirroring the neutral-default
/// style of `PostListRow.fixture` (`PostContextMenuBuilderTests.swift`) and
/// `PostDetailCommentRow.fixture` (`ShareCardAncestryTests.swift`).
extension PostDetailHeaderRow {
    static func fixture(
        serverPostId: Int64 = 1,
        title: String = "Test post",
        body: String? = nil,
        url: String? = nil,
        thumbnailUrl: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        communityName: String = "community",
        communityTitle: String? = nil,
        communityActorId: String? = "https://example.com/c/community",
        creatorName: String = "creator",
        creatorActorId: String? = "https://example.com/u/creator",
        score: Int64 = 0,
        numberOfComments: Int64 = 0,
        isNsfw: Bool = false,
        published: Date = Date(timeIntervalSince1970: 0)
    ) -> PostDetailHeaderRow {
        PostDetailHeaderRow(
            id: serverPostId,
            serverPostId: serverPostId,
            title: title,
            body: body,
            originalPostUrl: "https://example.com/post/\(serverPostId)",
            url: url,
            thumbnailUrl: thumbnailUrl,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            altText: nil,
            communityName: communityName,
            communityTitle: communityTitle,
            communityActorId: communityActorId,
            serverCommunityId: 1,
            creatorName: creatorName,
            creatorPersonId: 1,
            creatorActorId: creatorActorId,
            score: score,
            numberOfComments: numberOfComments,
            voteStatus: nil,
            isSaved: false,
            isRemoved: false,
            isLocked: false,
            isFeaturedCommunity: false,
            isFeaturedLocal: false,
            isDeleted: false,
            isNsfw: isNsfw,
            published: published
        )
    }
}

@MainActor
struct ShareCardContentTests {
    private let permalink = URL(string: "https://example.com/post/1")!

    // MARK: postRow builder

    @Test
    func postRowBuilder_mapsQualifiedHandlesAndPermalink() {
        let row = PostListRow.fixture(
            communityName: "linux",
            communityActorId: "https://lemmy.ml/c/linux",
            creatorName: "alice",
            creatorActorId: "https://lemmy.world/u/alice"
        )

        let content = ShareCardContent(postRow: row, permalink: permalink)

        #expect(content.kind == .post)
        #expect(content.post?.communityName == "linux")
        #expect(content.post?.communityHandle == "c/linux@lemmy.ml")
        #expect(content.post?.creatorHandle == "u/alice@lemmy.world")
        #expect(content.post?.permalink == permalink)
        #expect(content.chain.isEmpty)
    }

    @Test
    func postRowBuilder_missingActorIds_fallsBackToBareHandle() {
        let row = PostListRow.fixture(communityActorId: nil, creatorName: "bob", creatorActorId: nil)
        let content = ShareCardContent(postRow: row, permalink: permalink)

        #expect(content.post?.communityHandle == "c/community")
        #expect(content.post?.creatorHandle == "u/bob")
    }

    @Test
    func postRowBuilder_noCreatorName_yieldsNilCreatorHandle() {
        let row = PostListRow.fixture(creatorName: nil)
        let content = ShareCardContent(postRow: row, permalink: permalink)
        #expect(content.post?.creatorHandle == nil)
    }

    @Test
    func postRowBuilder_mapsIsNsfw() {
        let nsfwRow = PostListRow(
            id: 1, serverPostId: 1, title: "t", body: nil,
            originalPostUrl: "https://example.com/post/1", url: nil, thumbnailUrl: nil,
            urlEmbedTitle: nil, urlEmbedDescription: nil, altText: nil,
            communityName: "c", communityActorId: nil, serverCommunityId: 1,
            creatorPersonId: 1, creatorName: nil, creatorActorId: nil,
            score: 0, numberOfComments: 0, voteStatus: nil,
            isRead: false, isSaved: false, isRemoved: false, isLocked: false,
            isFeaturedCommunity: false, isFeaturedLocal: false, isDeleted: false,
            isNsfw: true, published: Date(timeIntervalSince1970: 0)
        )
        let content = ShareCardContent(postRow: nsfwRow, permalink: permalink)
        #expect(content.post?.isNsfw == true)
    }

    @Test
    func postRowBuilder_imageUrl_isDetectedAsMedia() {
        let row = PostListRow.fixture()
        let imageRow = PostListRow(
            id: row.id, serverPostId: row.serverPostId, title: row.title, body: row.body,
            originalPostUrl: row.originalPostUrl, url: "https://example.com/photo.jpg", thumbnailUrl: nil,
            urlEmbedTitle: nil, urlEmbedDescription: nil, altText: nil,
            communityName: row.communityName, communityActorId: row.communityActorId,
            serverCommunityId: row.serverCommunityId, creatorPersonId: row.creatorPersonId,
            creatorName: row.creatorName, creatorActorId: row.creatorActorId,
            score: row.score, numberOfComments: row.numberOfComments, voteStatus: nil,
            isRead: false, isSaved: row.isSaved, isRemoved: false, isLocked: false,
            isFeaturedCommunity: false, isFeaturedLocal: false, isDeleted: false,
            isNsfw: false, published: row.published
        )
        let content = ShareCardContent(postRow: imageRow, permalink: permalink)
        #expect(content.post?.mediaUrl == URL(string: "https://example.com/photo.jpg"))
        // PostListRow carries no image dimensions, so aspect is never "wide".
        #expect(content.post?.mediaAspectIsWide == false)
    }

    @Test
    func postRowBuilder_linkPost_hasNoMediaUrl() {
        let row = PostListRow.fixture()
        let linkRow = PostListRow(
            id: row.id, serverPostId: row.serverPostId, title: row.title, body: row.body,
            originalPostUrl: row.originalPostUrl, url: "https://example.com/article", thumbnailUrl: nil,
            urlEmbedTitle: "An article", urlEmbedDescription: nil, altText: nil,
            communityName: row.communityName, communityActorId: row.communityActorId,
            serverCommunityId: row.serverCommunityId, creatorPersonId: row.creatorPersonId,
            creatorName: row.creatorName, creatorActorId: row.creatorActorId,
            score: row.score, numberOfComments: row.numberOfComments, voteStatus: nil,
            isRead: false, isSaved: row.isSaved, isRemoved: false, isLocked: false,
            isFeaturedCommunity: false, isFeaturedLocal: false, isDeleted: false,
            isNsfw: false, published: row.published
        )
        let content = ShareCardContent(postRow: linkRow, permalink: permalink)
        #expect(content.post?.mediaUrl == nil)
    }

    // MARK: headerRow builder

    @Test
    func headerRowBuilder_prefersCommunityTitleOverName() {
        let row = PostDetailHeaderRow.fixture(communityName: "linux", communityTitle: "Linux Community")
        let content = ShareCardContent(headerRow: row, permalink: permalink)
        #expect(content.post?.communityName == "Linux Community")
        // The handle always uses the slug, never the display title.
        #expect(content.post?.communityHandle == "c/linux@example.com")
    }

    @Test
    func headerRowBuilder_blankCommunityTitle_fallsBackToName() {
        let row = PostDetailHeaderRow.fixture(communityName: "linux", communityTitle: "")
        let content = ShareCardContent(headerRow: row, permalink: permalink)
        #expect(content.post?.communityName == "linux")
    }

    @Test
    func headerRowBuilder_wideImageAspect_isDetected() {
        let wideRow = PostDetailHeaderRow.fixture(
            url: "https://example.com/wide.jpg",
            imageWidth: 1600,
            imageHeight: 900
        )
        let squareRow = PostDetailHeaderRow.fixture(
            url: "https://example.com/square.jpg",
            imageWidth: 800,
            imageHeight: 800
        )

        #expect(ShareCardContent(headerRow: wideRow, permalink: permalink).post?.mediaAspectIsWide == true)
        #expect(ShareCardContent(headerRow: squareRow, permalink: permalink).post?.mediaAspectIsWide == false)
    }

    @Test
    func headerRowBuilder_bodyPlain_stripsMarkdown() {
        let row = PostDetailHeaderRow.fixture(body: "**bold** and _italic_")
        let content = ShareCardContent(headerRow: row, permalink: permalink)
        #expect(content.post?.bodyPlain == "bold and italic")
    }

    // MARK: comment builder

    @Test
    func commentBuilder_ordersChainRootMostFirstWithDestinationLast() throws {
        let ancestors = [
            PostDetailCommentRow.fixture(id: 1, depth: 1),
            PostDetailCommentRow.fixture(id: 2, depth: 2),
        ]
        let comment = PostDetailCommentRow.fixture(id: 3, depth: 3)
        let commentPermalink = try #require(URL(string: "https://example.com/comment/3"))

        let content = ShareCardContent(
            comment: comment,
            ancestors: ancestors,
            header: nil,
            permalink: commentPermalink
        )

        #expect(content.kind == .comment)
        #expect(content.post == nil)
        #expect(content.chain.count == 3)
        #expect(content.chain.map(\.isDestination) == [false, false, true])
        #expect(content.chain.last?.permalink == commentPermalink)
        #expect(content.chain.dropLast().allSatisfy { $0.permalink == nil })
    }

    @Test
    func commentBuilder_withHeader_includesPostSummary() {
        let comment = PostDetailCommentRow.fixture(id: 1, depth: 1)
        let header = PostDetailHeaderRow.fixture(title: "The post title")
        let content = ShareCardContent(comment: comment, ancestors: [], header: header, permalink: permalink)

        #expect(content.post?.title == "The post title")
        #expect(content.chain.count == 1)
        #expect(content.chain[0].isDestination == true)
    }

    @Test
    func commentBuilder_chainItem_mapsAuthorHandleScoreAndBody() throws {
        let comment = PostDetailCommentRow.fixture(id: 1, depth: 1, score: 42, body: "hello world")
        let content = ShareCardContent(comment: comment, ancestors: [], header: nil, permalink: permalink)

        let item = try #require(content.chain.first)
        #expect(item.authorHandle == "u/user1@example.com")
        #expect(item.score == 42)
        #expect(item.bodyPlain == "hello world")
    }

    @Test
    func commentBuilder_deletedAuthor_yieldsNilAuthorHandle() {
        let comment = PostDetailCommentRow.fixture(id: 1, depth: 1, hasCreatorName: false)
        let content = ShareCardContent(comment: comment, ancestors: [], header: nil, permalink: permalink)
        #expect(content.chain.first?.authorHandle == nil)
    }
}
