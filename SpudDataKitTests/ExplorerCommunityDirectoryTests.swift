//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudDataKit

final class ExplorerCommunityDirectoryTests: XCTestCase {
    private var nextId: Int64 = 0

    private func row(
        _ name: String,
        host: String = "lemmy.world",
        title: String? = nil,
        members: Int64 = 0,
        week: Int64 = 0,
        month: Int64 = 0,
        posts: Int64 = 0,
        score: Double = 0,
        nsfw: Bool = false,
        suspicious: Bool = false
    ) -> CommunityListRow {
        nextId += 1
        return CommunityListRow(
            id: nextId,
            communityUrl: "https://\(host)/c/\(name)",
            instanceHost: host,
            name: name,
            title: title,
            descriptionText: nil,
            iconUrl: nil,
            isNsfw: nsfw,
            isSuspicious: suspicious,
            numberOfSubscribers: members,
            numberOfPosts: posts,
            numberOfComments: 0,
            usersActiveWeek: week,
            usersActiveMonth: month,
            score: score
        )
    }

    // MARK: - Sorting

    func test_sortByMembers_descending() {
        let rows = [row("a", members: 10), row("b", members: 99), row("c", members: 50)]
        let sorted = ExplorerCommunityDirectory.apply(
            to: rows, query: "", filter: .init(), sort: .members, dedupeSameName: false
        )
        XCTAssertEqual(sorted.map(\.name), ["b", "c", "a"])
    }

    func test_sortByMostActive_descending() {
        let rows = [row("a", week: 10), row("b", week: 99), row("c", week: 50)]
        let sorted = ExplorerCommunityDirectory.apply(
            to: rows, query: "", filter: .init(), sort: .mostActive, dedupeSameName: false
        )
        XCTAssertEqual(sorted.map(\.name), ["b", "c", "a"])
    }

    func test_sortByName_caseInsensitiveAscending_usesDisplayName() {
        let rows = [row("beta", title: "Beta"), row("alpha", title: "alpha")]
        let sorted = ExplorerCommunityDirectory.apply(
            to: rows, query: "", filter: .init(), sort: .name, dedupeSameName: false
        )
        XCTAssertEqual(sorted.map(\.name), ["alpha", "beta"])
    }

    // MARK: - Filtering

    func test_filterHideNsfw() {
        let rows = [row("clean"), row("naughty", nsfw: true)]
        let filtered = ExplorerCommunityDirectory.apply(
            to: rows, query: "", filter: .init(hideNsfw: true), sort: .recommended, dedupeSameName: false
        )
        XCTAssertEqual(filtered.map(\.name), ["clean"])
    }

    func test_filterHideSuspicious() {
        let rows = [row("legit"), row("spammy", suspicious: true)]
        let filtered = ExplorerCommunityDirectory.apply(
            to: rows, query: "", filter: .init(hideSuspicious: true), sort: .recommended, dedupeSameName: false
        )
        XCTAssertEqual(filtered.map(\.name), ["legit"])
    }

    // MARK: - Search

    func test_query_matchesNameTitleAndHost() {
        let rows = [
            row("technology", host: "lemmy.world", title: "Technology"),
            row("gaming", host: "sopuli.xyz", title: "Gaming"),
        ]
        XCTAssertEqual(
            ExplorerCommunityDirectory.apply(to: rows, query: "sopuli", filter: .init(), sort: .recommended, dedupeSameName: false).map(\.name),
            ["gaming"]
        )
        XCTAssertEqual(
            ExplorerCommunityDirectory.apply(to: rows, query: "Techno", filter: .init(), sort: .recommended, dedupeSameName: false).map(\.name),
            ["technology"]
        )
    }

    // MARK: - Same-name dedupe

    func test_dedupe_collapsesSameNameToBusiestServer() throws {
        let rows = [
            row("gaming", host: "lemmy.ml", members: 44000, week: 4200),
            row("gaming", host: "lemmy.world", members: 201_000, week: 14000),
            row("gaming", host: "beehaw.org", members: 19000, week: 2100),
        ]
        let result = ExplorerCommunityDirectory.apply(
            to: rows, query: "", filter: .init(), sort: .recommended, dedupeSameName: true
        )
        XCTAssertEqual(result.count, 1)
        let canonical = try XCTUnwrap(result.first)
        XCTAssertEqual(canonical.instanceHost, "lemmy.world", "canonical is the busiest server")
        XCTAssertEqual(canonical.alsoOnServerCount, 2)
        XCTAssertEqual(canonical.groupTotalSubscribers, 264_000)
    }

    func test_dedupeOff_keepsAllVariants() {
        let rows = [row("gaming", host: "lemmy.world"), row("gaming", host: "lemmy.ml")]
        let result = ExplorerCommunityDirectory.apply(
            to: rows, query: "", filter: .init(), sort: .name, dedupeSameName: false
        )
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Trending

    func test_trending_ranksByActiveWeek_excludingSuspiciousAndBelowFloor() {
        let rows = [
            row("big", members: 300_000, week: 5000),
            row("buzzy", members: 20000, week: 9000),
            row("spam", week: 99000, suspicious: true),
            row("quiet", week: 10),
        ]
        let trending = ExplorerCommunityDirectory.trending(in: rows, limit: 10, minActiveWeek: 100)
        XCTAssertEqual(trending.map(\.name), ["buzzy", "big"])
    }

    func test_trending_collapsesSameName() {
        let rows = [
            row("gaming", host: "lemmy.world", members: 201_000, week: 14000),
            row("gaming", host: "lemmy.ml", members: 44000, week: 4200),
        ]
        let trending = ExplorerCommunityDirectory.trending(in: rows, limit: 10, minActiveWeek: 100)
        XCTAssertEqual(trending.count, 1)
        XCTAssertEqual(trending.first?.instanceHost, "lemmy.world")
    }

    // MARK: - Rising

    func test_rising_favoursSmallHighEngagement_excludingLarge() {
        let rows = [
            row("huge", members: 500_000, week: 20000), // excluded by size ceiling
            row("gem", members: 8000, week: 4000), // high engagement for its size
            row("ok", members: 20000, week: 3000),
        ]
        let rising = ExplorerCommunityDirectory.rising(
            in: rows, limit: 10, maxSubscribers: 25000, minActiveWeek: 100
        )
        XCTAssertEqual(rising.first?.name, "gem")
        XCTAssertFalse(rising.contains { $0.name == "huge" })
    }

    // MARK: - Variants (compare sheet)

    func test_variants_returnsSameNameRankedByActivity() {
        let rows = [
            row("gaming", host: "lemmy.ml", week: 4200),
            row("gaming", host: "lemmy.world", week: 14000),
            row("technology", host: "lemmy.world", week: 22000),
        ]
        let variants = ExplorerCommunityDirectory.variants(of: "gaming", in: rows)
        XCTAssertEqual(variants.map(\.instanceHost), ["lemmy.world", "lemmy.ml"])
    }

    // MARK: - Browse by instance

    func test_topInstances_ranksByWeeklyActive_andAggregatesCounts() throws {
        let rows = [
            row("a", host: "lemmy.world", members: 100, week: 50),
            row("b", host: "lemmy.world", members: 200, week: 80),
            row("c", host: "beehaw.org", members: 500, week: 300),
        ]
        let instances = ExplorerCommunityDirectory.topInstances(in: rows, limit: 10)
        XCTAssertEqual(instances.map(\.host), ["beehaw.org", "lemmy.world"], "busiest server first")

        let world = try XCTUnwrap(instances.first { $0.host == "lemmy.world" })
        XCTAssertEqual(world.communityCount, 2)
        XCTAssertEqual(world.totalSubscribers, 300)
        XCTAssertEqual(world.totalActiveWeek, 130)
    }

    func test_topInstances_excludesSuspiciousAndNsfwFromAggregation() throws {
        let rows = [
            row("clean", host: "x.org", members: 100, week: 50),
            row("naughty", host: "x.org", members: 999, week: 999, nsfw: true),
            row("spam", host: "spam.org", week: 999, suspicious: true),
        ]
        let instances = ExplorerCommunityDirectory.topInstances(in: rows, limit: 10)
        XCTAssertEqual(instances.map(\.host), ["x.org"], "an instance with only unsafe communities drops out")

        let safe = try XCTUnwrap(instances.first)
        XCTAssertEqual(safe.communityCount, 1, "the NSFW community is not counted")
        XCTAssertEqual(safe.totalSubscribers, 100)
    }

    func test_topInstances_respectsLimit() {
        let rows = [
            row("a", host: "h1.org", week: 100),
            row("b", host: "h2.org", week: 90),
            row("c", host: "h3.org", week: 80),
        ]
        XCTAssertEqual(ExplorerCommunityDirectory.topInstances(in: rows, limit: 2).count, 2)
    }

    func test_communitiesOnInstance_filtersToHost_excludesUnsafe_andSorts() {
        let rows = [
            row("a", host: "lemmy.world", week: 10),
            row("b", host: "lemmy.world", week: 90),
            row("c", host: "beehaw.org", week: 50),
            row("d", host: "lemmy.world", week: 99, nsfw: true),
        ]
        let result = ExplorerCommunityDirectory.communities(
            onInstance: "lemmy.world", in: rows, sort: .mostActive
        )
        XCTAssertEqual(result.map(\.name), ["b", "a"], "host-filtered, NSFW dropped, sorted by activity")
    }
}
