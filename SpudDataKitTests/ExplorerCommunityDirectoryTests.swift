//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct ExplorerCommunityDirectoryTests {
    private var nextId: Int64 = 0

    private mutating func row(
        _ name: String,
        host: String = "lemmy.world",
        title: String? = nil,
        members: Int64 = 0,
        week: Int64 = 0,
        month: Int64 = 0,
        posts: Int64 = 0,
        score: Double = 0,
        nsfw: Bool = false,
        suspicious: Bool = false,
        published: Date? = nil
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
            score: score,
            publishedAt: published
        )
    }

    // MARK: - Sorting

    @Test
    mutating func sortByMembers_descending() {
        let rows = [row("a", members: 10), row("b", members: 99), row("c", members: 50)]
        let sorted = ExplorerCommunityDirectory.apply(
            to: rows, query: "", filter: .init(), sort: .members, dedupeSameName: false
        )
        #expect(sorted.map(\.name) == ["b", "c", "a"])
    }

    @Test
    mutating func sortByMostActive_descending() {
        let rows = [row("a", week: 10), row("b", week: 99), row("c", week: 50)]
        let sorted = ExplorerCommunityDirectory.apply(
            to: rows, query: "", filter: .init(), sort: .mostActive, dedupeSameName: false
        )
        #expect(sorted.map(\.name) == ["b", "c", "a"])
    }

    @Test
    mutating func sortByName_caseInsensitiveAscending_usesDisplayName() {
        let rows = [row("beta", title: "Beta"), row("alpha", title: "alpha")]
        let sorted = ExplorerCommunityDirectory.apply(
            to: rows, query: "", filter: .init(), sort: .name, dedupeSameName: false
        )
        #expect(sorted.map(\.name) == ["alpha", "beta"])
    }

    @Test
    mutating func sortByNewest_mostRecentFirst_undatedLast() {
        let day: TimeInterval = 86400
        let rows = [
            row("old", published: Date(timeIntervalSince1970: 1 * day)),
            row("undated", published: nil),
            row("new", published: Date(timeIntervalSince1970: 100 * day)),
            row("mid", published: Date(timeIntervalSince1970: 50 * day)),
        ]
        let sorted = ExplorerCommunityDirectory.apply(
            to: rows, query: "", filter: .init(), sort: .newest, dedupeSameName: false
        )
        #expect(sorted.map(\.name) == ["new", "mid", "old", "undated"])
    }

    @Test
    mutating func sorted_reordersInPlace_withoutFiltering() {
        let rows = [row("a", members: 10), row("b", members: 99), row("c", members: 50)]
        let resorted = ExplorerCommunityDirectory.sorted(rows, by: .members)
        #expect(resorted.map(\.name) == ["b", "c", "a"])
        #expect(resorted.count == rows.count, "re-sort keeps every row")
    }

    // MARK: - Filtering

    @Test
    mutating func filterHideNsfw() {
        let rows = [row("clean"), row("naughty", nsfw: true)]
        let filtered = ExplorerCommunityDirectory.apply(
            to: rows, query: "", filter: .init(hideNsfw: true), sort: .recommended, dedupeSameName: false
        )
        #expect(filtered.map(\.name) == ["clean"])
    }

    @Test
    mutating func filterHideSuspicious() {
        let rows = [row("legit"), row("spammy", suspicious: true)]
        let filtered = ExplorerCommunityDirectory.apply(
            to: rows, query: "", filter: .init(hideSuspicious: true), sort: .recommended, dedupeSameName: false
        )
        #expect(filtered.map(\.name) == ["legit"])
    }

    // MARK: - Search

    @Test
    mutating func query_matchesNameTitleAndHost() {
        let rows = [
            row("technology", host: "lemmy.world", title: "Technology"),
            row("gaming", host: "sopuli.xyz", title: "Gaming"),
        ]
        #expect(
            ExplorerCommunityDirectory.apply(to: rows, query: "sopuli", filter: .init(), sort: .recommended, dedupeSameName: false).map(\.name) == ["gaming"]
        )
        #expect(
            ExplorerCommunityDirectory.apply(to: rows, query: "Techno", filter: .init(), sort: .recommended, dedupeSameName: false).map(\.name) == ["technology"]
        )
    }

    // MARK: - Same-name dedupe

    @Test
    mutating func dedupe_collapsesSameNameToBusiestServer() throws {
        let rows = [
            row("gaming", host: "lemmy.ml", members: 44000, week: 4200),
            row("gaming", host: "lemmy.world", members: 201_000, week: 14000),
            row("gaming", host: "beehaw.org", members: 19000, week: 2100),
        ]
        let result = ExplorerCommunityDirectory.apply(
            to: rows, query: "", filter: .init(), sort: .recommended, dedupeSameName: true
        )
        #expect(result.count == 1)
        let canonical = try #require(result.first)
        #expect(canonical.instanceHost == "lemmy.world", "canonical is the busiest server")
        #expect(canonical.alsoOnServerCount == 2)
        #expect(canonical.groupTotalSubscribers == 264_000)
    }

    @Test
    mutating func dedupeOff_keepsAllVariants() {
        let rows = [row("gaming", host: "lemmy.world"), row("gaming", host: "lemmy.ml")]
        let result = ExplorerCommunityDirectory.apply(
            to: rows, query: "", filter: .init(), sort: .name, dedupeSameName: false
        )
        #expect(result.count == 2)
    }

    // MARK: - Trending

    @Test
    mutating func trending_ranksByActiveWeek_excludingSuspiciousAndBelowFloor() {
        let rows = [
            row("big", members: 300_000, week: 5000),
            row("buzzy", members: 20000, week: 9000),
            row("spam", week: 99000, suspicious: true),
            row("quiet", week: 10),
        ]
        let trending = ExplorerCommunityDirectory.trending(in: rows, limit: 10, minActiveWeek: 100)
        #expect(trending.map(\.name) == ["buzzy", "big"])
    }

    @Test
    mutating func trending_collapsesSameName() {
        let rows = [
            row("gaming", host: "lemmy.world", members: 201_000, week: 14000),
            row("gaming", host: "lemmy.ml", members: 44000, week: 4200),
        ]
        let trending = ExplorerCommunityDirectory.trending(in: rows, limit: 10, minActiveWeek: 100)
        #expect(trending.count == 1)
        #expect(trending.first?.instanceHost == "lemmy.world")
    }

    // MARK: - Rising

    @Test
    mutating func rising_favoursSmallHighEngagement_excludingLarge() {
        let rows = [
            row("huge", members: 500_000, week: 20000), // excluded by size ceiling
            row("gem", members: 8000, week: 4000), // high engagement for its size
            row("ok", members: 20000, week: 3000),
        ]
        let rising = ExplorerCommunityDirectory.rising(
            in: rows, limit: 10, maxSubscribers: 25000, minActiveWeek: 100
        )
        #expect(rising.first?.name == "gem")
        #expect(!(rising.contains { $0.name == "huge" }))
    }

    // MARK: - Variants (compare sheet)

    @Test
    mutating func variants_returnsSameNameRankedByActivity() {
        let rows = [
            row("gaming", host: "lemmy.ml", week: 4200),
            row("gaming", host: "lemmy.world", week: 14000),
            row("technology", host: "lemmy.world", week: 22000),
        ]
        let variants = ExplorerCommunityDirectory.variants(of: "gaming", in: rows)
        #expect(variants.map(\.instanceHost) == ["lemmy.world", "lemmy.ml"])
    }

    // MARK: - Browse by instance

    @Test
    mutating func topInstances_ranksByWeeklyActive_andAggregatesCounts() throws {
        let rows = [
            row("a", host: "lemmy.world", members: 100, week: 50),
            row("b", host: "lemmy.world", members: 200, week: 80),
            row("c", host: "beehaw.org", members: 500, week: 300),
        ]
        let instances = ExplorerCommunityDirectory.topInstances(in: rows, limit: 10)
        #expect(instances.map(\.host) == ["beehaw.org", "lemmy.world"], "busiest server first")

        let world = try #require(instances.first { $0.host == "lemmy.world" })
        #expect(world.communityCount == 2)
        #expect(world.totalSubscribers == 300)
        #expect(world.totalActiveWeek == 130)
    }

    @Test
    mutating func topInstances_excludesSuspiciousAndNsfwFromAggregation() throws {
        let rows = [
            row("clean", host: "x.org", members: 100, week: 50),
            row("naughty", host: "x.org", members: 999, week: 999, nsfw: true),
            row("spam", host: "spam.org", week: 999, suspicious: true),
        ]
        let instances = ExplorerCommunityDirectory.topInstances(in: rows, limit: 10)
        #expect(instances.map(\.host) == ["x.org"], "an instance with only unsafe communities drops out")

        let safe = try #require(instances.first)
        #expect(safe.communityCount == 1, "the NSFW community is not counted")
        #expect(safe.totalSubscribers == 100)
    }

    @Test
    mutating func topInstances_respectsLimit() {
        let rows = [
            row("a", host: "h1.org", week: 100),
            row("b", host: "h2.org", week: 90),
            row("c", host: "h3.org", week: 80),
        ]
        #expect(ExplorerCommunityDirectory.topInstances(in: rows, limit: 2).count == 2)
    }

    @Test
    mutating func communitiesOnInstance_filtersToHost_excludesUnsafe_andSorts() {
        let rows = [
            row("a", host: "lemmy.world", week: 10),
            row("b", host: "lemmy.world", week: 90),
            row("c", host: "beehaw.org", week: 50),
            row("d", host: "lemmy.world", week: 99, nsfw: true),
        ]
        let result = ExplorerCommunityDirectory.communities(
            onInstance: "lemmy.world", in: rows, sort: .mostActive
        )
        #expect(result.map(\.name) == ["b", "a"], "host-filtered, NSFW dropped, sorted by activity")
    }

    // MARK: - Because you follow

    @Test
    mutating func becauseYouFollow_recommendsSameHostNotFollowed_byActivity() {
        let rows = [
            row("tech", host: "lemmy.world", week: 1000),
            row("memes", host: "lemmy.world", week: 5000),
            row("followed", host: "lemmy.world", week: 9000),
            row("other", host: "sopuli.xyz", week: 8000),
        ]
        let result = ExplorerCommunityDirectory.becauseYouFollow(
            in: rows,
            followedHosts: ["lemmy.world"],
            excludingUrls: ["https://lemmy.world/c/followed"],
            limit: 10
        )
        #expect(result.map(\.name) == ["memes", "tech"], "same-host, not-followed, busiest-first")
    }

    @Test
    mutating func becauseYouFollow_emptyWhenNoFollowedHosts() {
        let rows = [row("tech", host: "lemmy.world", week: 1000)]
        #expect(
            ExplorerCommunityDirectory.becauseYouFollow(
                in: rows, followedHosts: [], excludingUrls: [], limit: 10
            ).isEmpty
        )
    }

    @Test
    mutating func becauseYouFollow_excludesSuspiciousAndNsfw() {
        let rows = [
            row("ok", host: "lemmy.world", week: 100),
            row("naughty", host: "lemmy.world", week: 9000, nsfw: true),
            row("spam", host: "lemmy.world", week: 9000, suspicious: true),
        ]
        let result = ExplorerCommunityDirectory.becauseYouFollow(
            in: rows, followedHosts: ["lemmy.world"], excludingUrls: [], limit: 10
        )
        #expect(result.map(\.name) == ["ok"])
    }
}
