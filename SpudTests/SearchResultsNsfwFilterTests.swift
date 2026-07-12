//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUtilKit
import Testing
@testable import Spud

/// Covers the search NSFW policy: NSFW *posts* are now KEPT (they render blurred
/// through the shared feed cell), while NSFW *communities* are still withheld when
/// the user has not opted in. Only the post behavior changed — posts used to be
/// dropped alongside communities.
@MainActor
struct SearchResultsNsfwFilterTests {
    // MARK: Helpers

    private func makeRow(id: Int64, isNsfw: Bool) -> PostListRow {
        PostListRow(
            id: id,
            serverPostId: id,
            title: isNsfw ? "NSFW post \(id)" : "SFW post \(id)",
            body: nil,
            originalPostUrl: "https://example.com/post/\(id)",
            url: nil,
            thumbnailUrl: nil,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            altText: nil,
            communityName: isNsfw ? "nsfw" : "sfw",
            communityActorId: "https://example.com/c/\(isNsfw ? "nsfw" : "sfw")",
            serverCommunityId: id,
            creatorPersonId: id,
            creatorName: "alice",
            creatorActorId: "https://example.com/u/alice",
            score: 0,
            numberOfComments: 0,
            voteStatus: nil,
            isRead: false,
            isSaved: false,
            isRemoved: false,
            isLocked: false,
            isFeaturedCommunity: false,
            isFeaturedLocal: false,
            isDeleted: false,
            isNsfw: isNsfw,
            published: .distantPast
        )
    }

    private func makeSfwPost(id: Int64) -> SearchPostResult {
        SearchPostResult(row: makeRow(id: id, isNsfw: false))
    }

    private func makeNsfwPost(id: Int64) -> SearchPostResult {
        SearchPostResult(row: makeRow(id: id, isNsfw: true))
    }

    private func makeSfwCommunity(id: Int32) -> SearchCommunityResult {
        SearchCommunityResult(
            serverCommunityId: id,
            name: "sfwcommunity\(id)",
            qualifiedName: "!sfwcommunity\(id)@example.com",
            instance: InstanceActorId(from: "example.com")!,
            subscribersText: "100",
            iconUrl: nil,
            followState: .notFollowing,
            isNsfw: false
        )
    }

    private func makeNsfwCommunity(id: Int32) -> SearchCommunityResult {
        SearchCommunityResult(
            serverCommunityId: id,
            name: "nsfwcommunity\(id)",
            qualifiedName: "!nsfwcommunity\(id)@example.com",
            instance: InstanceActorId(from: "example.com")!,
            subscribersText: "50",
            iconUrl: nil,
            followState: .notFollowing,
            isNsfw: true
        )
    }

    // MARK: Tests

    @Test
    func filteringNsfw_true_keepsNsfwPostsMarkedForBlur_dropsNsfwCommunities() {
        var results = SearchResults()
        results.posts = [makeSfwPost(id: 1), makeNsfwPost(id: 2), makeSfwPost(id: 3)]
        results.communities = [makeSfwCommunity(id: 10), makeNsfwCommunity(id: 11)]

        let filtered = results.filteringNsfw(true)

        // Posts are no longer dropped: the NSFW post is RETURNED, and it is still
        // flagged NSFW so the shared feed cell blurs it (respecting the blur preference
        // and tap-to-reveal) rather than hiding it.
        #expect(filtered.posts.count == 3)
        #expect(filtered.posts.contains { $0.isNsfw })
        #expect(filtered.posts.first { $0.serverPostId == 2 }?.isNsfw == true)

        // Communities still drop: the community cell has no blur affordance.
        #expect(filtered.communities.count == 1)
        #expect(filtered.communities.allSatisfy { !$0.isNsfw })
    }

    @Test
    func filteringNsfw_false_keepsAll() {
        var results = SearchResults()
        results.posts = [makeSfwPost(id: 1), makeNsfwPost(id: 2)]
        results.communities = [makeSfwCommunity(id: 10), makeNsfwCommunity(id: 11)]

        let filtered = results.filteringNsfw(false)

        #expect(filtered.posts.count == 2)
        #expect(filtered.communities.count == 2)
    }

    @Test
    func filteringNsfw_true_preservesPostsUsersAndComments() {
        // Posts are kept (blurred, not dropped); users and comments have no NSFW flag
        // and are left untouched. Only the NSFW community is withheld.
        var results = SearchResults()
        results.posts = [makeNsfwPost(id: 1)]
        results.communities = [makeNsfwCommunity(id: 10)]

        let filtered = results.filteringNsfw(true)

        #expect(filtered.posts.count == 1)
        #expect(filtered.posts[0].isNsfw)
        #expect(filtered.communities.isEmpty)
        #expect(filtered.users.isEmpty)
        #expect(filtered.comments.isEmpty)
    }

    @Test
    func filteringNsfw_true_allSfw_keepsAll() {
        var results = SearchResults()
        results.posts = [makeSfwPost(id: 1), makeSfwPost(id: 2)]
        results.communities = [makeSfwCommunity(id: 10)]

        let filtered = results.filteringNsfw(true)

        #expect(filtered.posts.count == 2)
        #expect(filtered.communities.count == 1)
    }
}
