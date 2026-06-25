//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import XCTest
@testable import Spud

@MainActor
final class SearchResultsNsfwFilterTests: XCTestCase {
    // MARK: Helpers

    private func makeSfwPost(id: Int32) -> SearchPostResult {
        SearchPostResult(
            serverPostId: id,
            title: "SFW post \(id)",
            communityName: "sfw",
            score: 0,
            numberOfComments: 0,
            published: .distantPast,
            thumbnailUrl: nil,
            isNsfw: false
        )
    }

    private func makeNsfwPost(id: Int32) -> SearchPostResult {
        SearchPostResult(
            serverPostId: id,
            title: "NSFW post \(id)",
            communityName: "nsfw",
            score: 0,
            numberOfComments: 0,
            published: .distantPast,
            thumbnailUrl: nil,
            isNsfw: true
        )
    }

    private func makeSfwCommunity(id: Int32) -> SearchCommunityResult {
        SearchCommunityResult(
            serverCommunityId: id,
            name: "sfwcommunity\(id)",
            qualifiedName: "!sfwcommunity\(id)@example.com",
            instance: InstanceActorId(from: "example.com")!,
            subscribersText: "100",
            iconUrl: nil,
            subscribed: .NotSubscribed,
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
            subscribed: .NotSubscribed,
            isNsfw: true
        )
    }

    // MARK: Tests

    func test_filteringNsfw_true_dropsNsfwPostsAndCommunities() {
        var results = SearchResults()
        results.posts = [makeSfwPost(id: 1), makeNsfwPost(id: 2), makeSfwPost(id: 3)]
        results.communities = [makeSfwCommunity(id: 10), makeNsfwCommunity(id: 11)]

        let filtered = results.filteringNsfw(true)

        XCTAssertEqual(filtered.posts.count, 2)
        XCTAssertTrue(filtered.posts.allSatisfy { !$0.isNsfw })
        XCTAssertEqual(filtered.communities.count, 1)
        XCTAssertTrue(filtered.communities.allSatisfy { !$0.isNsfw })
    }

    func test_filteringNsfw_false_keepsAll() {
        var results = SearchResults()
        results.posts = [makeSfwPost(id: 1), makeNsfwPost(id: 2)]
        results.communities = [makeSfwCommunity(id: 10), makeNsfwCommunity(id: 11)]

        let filtered = results.filteringNsfw(false)

        XCTAssertEqual(filtered.posts.count, 2)
        XCTAssertEqual(filtered.communities.count, 2)
    }

    func test_filteringNsfw_true_preservesUsersAndComments() {
        // users and comments have no NSFW flag; they must be left untouched
        var results = SearchResults()
        results.posts = [makeNsfwPost(id: 1)]
        results.communities = [makeNsfwCommunity(id: 10)]
        // users / comments stay empty in this test; the filter must not crash on them

        let filtered = results.filteringNsfw(true)

        XCTAssertTrue(filtered.posts.isEmpty)
        XCTAssertTrue(filtered.communities.isEmpty)
        XCTAssertTrue(filtered.users.isEmpty)
        XCTAssertTrue(filtered.comments.isEmpty)
    }

    func test_filteringNsfw_true_allSfw_keepsAll() {
        var results = SearchResults()
        results.posts = [makeSfwPost(id: 1), makeSfwPost(id: 2)]
        results.communities = [makeSfwCommunity(id: 10)]

        let filtered = results.filteringNsfw(true)

        XCTAssertEqual(filtered.posts.count, 2)
        XCTAssertEqual(filtered.communities.count, 1)
    }
}
