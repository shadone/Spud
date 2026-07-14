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

/// Covers the search NSFW policy, which mirrors the feed exactly:
/// - **Show-NSFW off** (`filteringNsfw(true)`): NSFW posts *and* communities are
///   DROPPED — an opted-out user is never shown NSFW, matching the server-filtered
///   feed.
/// - **Show-NSFW on** (`filteringNsfw(false)`): NSFW posts are KEPT and stay
///   `isNsfw`-marked so the shared feed cell blurs them per the blur preference.
///
/// Regression guard: a prior revision dropped only NSFW *communities* while keeping
/// NSFW *posts* even with Show-NSFW off, so a raw NSFW thumbnail could reach a user
/// who had opted out (with blur also off). These tests pin the drop-on-opt-out.
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
            isNsfw: false,
            communityUrl: "https://example.com/c/sfwcommunity\(id)"
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
            isNsfw: true,
            communityUrl: "https://example.com/c/nsfwcommunity\(id)"
        )
    }

    // MARK: Tests

    @Test
    func filteringNsfw_true_dropsNsfwPostsAndCommunities() {
        var results = SearchResults()
        results.posts = [makeSfwPost(id: 1), makeNsfwPost(id: 2), makeSfwPost(id: 3)]
        results.communities = [makeSfwCommunity(id: 10), makeNsfwCommunity(id: 11)]

        let filtered = results.filteringNsfw(true)

        // Show-NSFW off: the NSFW post is DROPPED entirely (never rendered to an
        // opted-out user), and only the SFW posts survive.
        #expect(filtered.posts.count == 2)
        #expect(filtered.posts.allSatisfy { !$0.isNsfw })
        #expect(filtered.posts.contains { $0.serverPostId == 2 } == false)

        // The NSFW community is likewise withheld.
        #expect(filtered.communities.count == 1)
        #expect(filtered.communities.allSatisfy { !$0.isNsfw })
    }

    @Test
    func filteringNsfw_false_keepsNsfwPostsMarkedForBlur() {
        var results = SearchResults()
        results.posts = [makeSfwPost(id: 1), makeNsfwPost(id: 2)]
        results.communities = [makeSfwCommunity(id: 10), makeNsfwCommunity(id: 11)]

        let filtered = results.filteringNsfw(false)

        // Show-NSFW on: everything is kept, and the NSFW post is still flagged so the
        // shared feed cell blurs it (per the blur preference / tap-to-reveal).
        #expect(filtered.posts.count == 2)
        #expect(filtered.posts.first { $0.serverPostId == 2 }?.isNsfw == true)
        #expect(filtered.communities.count == 2)
    }

    @Test
    func filteringNsfw_true_dropsNsfwPost_leavesUsersAndCommentsUntouched() {
        // The lone NSFW post and NSFW community are dropped; users and comments have no
        // NSFW flag and are never filtered.
        var results = SearchResults()
        results.posts = [makeNsfwPost(id: 1)]
        results.communities = [makeNsfwCommunity(id: 10)]

        let filtered = results.filteringNsfw(true)

        #expect(filtered.posts.isEmpty)
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
