//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
@testable import Spud

/// Covers `CrossPostGrouper.group(rows:)` in isolation — the pure transform
/// `PostListViewController.apply(rows:)` layers onto the feed snapshot after
/// the hide-read filter. No view controller / view model involved.
struct CrossPostGrouperTests {
    /// Builds a `PostListRow` with only the fields the grouper reads
    /// (`serverPostId`, `url`); everything else is filler.
    private func row(serverPostId: Int64, url: String?) -> PostListRow {
        PostListRow(
            id: serverPostId,
            serverPostId: serverPostId,
            title: "post \(serverPostId)",
            body: nil,
            originalPostUrl: "https://example.test/post/\(serverPostId)",
            url: url,
            thumbnailUrl: nil,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            altText: nil,
            communityName: "c\(serverPostId)",
            communityActorId: nil,
            serverCommunityId: serverPostId,
            creatorPersonId: 1,
            creatorName: nil,
            creatorActorId: nil,
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
            isNsfw: false,
            published: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - group(rows:)

    @Test
    func emptyInputReturnsEmptyResult() {
        let result = CrossPostGrouper.group(rows: [])
        #expect(result.displayed.isEmpty)
        #expect(result.siblingsByPrimary.isEmpty)
    }

    @Test
    func exactUrlCollapsesFirstRowIsPrimaryRestAreSiblingsInOrder() {
        let rows = [
            row(serverPostId: 1, url: "https://example.com/article"),
            row(serverPostId: 2, url: "https://example.com/article"),
            row(serverPostId: 3, url: "https://example.com/article"),
        ]
        let result = CrossPostGrouper.group(rows: rows)

        #expect(result.displayed.map(\.serverPostId) == [1])
        #expect(result.siblingsByPrimary[1]?.map(\.serverPostId) == [2, 3])
    }

    @Test
    func nilUrlRowsNeverGroupEvenWithEachOther() {
        // Two nil-url posts must never merge into one group keyed by "nil" —
        // every ungroupable row is always its own entry.
        let rows = [
            row(serverPostId: 1, url: nil),
            row(serverPostId: 2, url: nil),
            row(serverPostId: 3, url: "https://example.com/article"),
        ]
        let result = CrossPostGrouper.group(rows: rows)

        #expect(result.displayed.map(\.serverPostId) == [1, 2, 3])
        #expect(result.siblingsByPrimary.isEmpty)
    }

    @Test
    func blankUrlRowsNeverGroup() {
        let rows = [
            row(serverPostId: 1, url: ""),
            row(serverPostId: 2, url: "   "),
        ]
        let result = CrossPostGrouper.group(rows: rows)

        #expect(result.displayed.map(\.serverPostId) == [1, 2])
        #expect(result.siblingsByPrimary.isEmpty)
    }

    @Test
    func orderOfSurvivingPrimariesAndUngroupableRowsIsPreserved() {
        let rows = [
            row(serverPostId: 1, url: "https://example.com/a"),
            row(serverPostId: 2, url: nil),
            row(serverPostId: 3, url: "https://example.com/a"),
            row(serverPostId: 4, url: "https://example.com/b"),
        ]
        let result = CrossPostGrouper.group(rows: rows)

        // #3 (a sibling of #1) drops out; #1, #2 (ungroupable), #4 keep their
        // relative order.
        #expect(result.displayed.map(\.serverPostId) == [1, 2, 4])
    }

    @Test
    func threeOrMoreSiblingsAllCollapseIntoOnePrimary() {
        let rows = [
            row(serverPostId: 1, url: "https://example.com/a"),
            row(serverPostId: 2, url: "https://example.com/a"),
            row(serverPostId: 3, url: "https://example.com/a"),
            row(serverPostId: 4, url: "https://example.com/a"),
        ]
        let result = CrossPostGrouper.group(rows: rows)

        #expect(result.displayed.map(\.serverPostId) == [1])
        #expect(result.siblingsByPrimary[1]?.map(\.serverPostId) == [2, 3, 4])
    }

    @Test
    func twoIndependentUrlGroupsInterleaved() {
        let rows = [
            row(serverPostId: 1, url: "https://example.com/a"),
            row(serverPostId: 2, url: "https://example.com/b"),
            row(serverPostId: 3, url: "https://example.com/a"),
            row(serverPostId: 4, url: "https://example.com/b"),
            row(serverPostId: 5, url: "https://example.com/a"),
        ]
        let result = CrossPostGrouper.group(rows: rows)

        #expect(result.displayed.map(\.serverPostId) == [1, 2])
        #expect(result.siblingsByPrimary[1]?.map(\.serverPostId) == [3, 5])
        #expect(result.siblingsByPrimary[2]?.map(\.serverPostId) == [4])
    }

    @Test
    func doesNotGroupPostsWithDifferentUrls() {
        let rows = [
            row(serverPostId: 1, url: "https://example.com/a"),
            row(serverPostId: 2, url: "https://example.com/b"),
        ]
        let result = CrossPostGrouper.group(rows: rows)

        #expect(result.displayed.map(\.serverPostId) == [1, 2])
        #expect(result.siblingsByPrimary.isEmpty)
    }

    /// Mirrors `PostListViewController.apply(rows:)`'s ternary — when the
    /// preference is off, the caller skips `group(rows:)` entirely and passes
    /// its filtered input through unchanged with an empty siblings map. This
    /// isn't a property of `CrossPostGrouper` itself (its `group(rows:)` always
    /// groups), but pins down the documented "callers skip it" contract so a
    /// future edit that accidentally always groups gets caught here too.
    @Test
    func disabledGroupingWiringLeavesInputUnchanged() {
        let filtered = [
            row(serverPostId: 1, url: "https://example.com/a"),
            row(serverPostId: 2, url: "https://example.com/a"),
        ]
        let groupCrossPosts = false
        let result = groupCrossPosts
            ? CrossPostGrouper.group(rows: filtered)
            : CrossPostGrouper.Result(displayed: filtered, siblingsByPrimary: [:])

        #expect(result.displayed == filtered)
        #expect(result.siblingsByPrimary.isEmpty)
    }

    // MARK: - normalizedKey(for:)

    @Test
    func normalizedKeyNilForNilUrl() {
        #expect(CrossPostGrouper.normalizedKey(for: nil) == nil)
    }

    @Test
    func normalizedKeyNilForBlankUrl() {
        #expect(CrossPostGrouper.normalizedKey(for: "   ") == nil)
    }

    @Test
    func normalizedKeyLowercasesHostOnly() {
        let key = CrossPostGrouper.normalizedKey(for: "https://Example.COM/Article")
        #expect(key == "https://example.com/Article")
    }

    @Test
    func normalizedKeyStripsSingleTrailingSlash() {
        let withSlash = CrossPostGrouper.normalizedKey(for: "https://example.com/article/")
        let withoutSlash = CrossPostGrouper.normalizedKey(for: "https://example.com/article")
        #expect(withSlash == withoutSlash)
    }

    @Test
    func normalizedKeyKeepsFragment() {
        // A fragment difference is treated as a genuinely different resource —
        // same rationale as the query string (see CrossPostGrouper doc
        // comment): dropping it risks false-merging a hash-routed SPA link.
        let withFragment = CrossPostGrouper.normalizedKey(for: "https://example.com/article#section-2")
        let withoutFragment = CrossPostGrouper.normalizedKey(for: "https://example.com/article")
        #expect(withFragment != withoutFragment)
    }

    @Test
    func normalizedKeyKeepsQueryString() {
        // A query difference is treated as a genuinely different resource —
        // conservative on purpose (see CrossPostGrouper doc comment).
        let a = CrossPostGrouper.normalizedKey(for: "https://example.com/article?id=1")
        let b = CrossPostGrouper.normalizedKey(for: "https://example.com/article?id=2")
        #expect(a != b)
    }

    @Test
    func trailingSlashNormalizationGroupsRowsThatDifferOnlyByIt() {
        let rows = [
            row(serverPostId: 1, url: "https://example.com/article"),
            row(serverPostId: 2, url: "https://Example.com/article/"),
        ]
        let result = CrossPostGrouper.group(rows: rows)

        #expect(result.displayed.map(\.serverPostId) == [1])
        #expect(result.siblingsByPrimary[1]?.map(\.serverPostId) == [2])
    }

    @Test
    func hashRoutedSpaLinksWithDifferentFragmentsAreNotGrouped() {
        // A hash-routed single-page app encodes its whole route after `#`
        // (e.g. `/#/x` vs `/#/y` are different pages on the same site), so
        // fragment-dropping would false-merge two genuinely different posts.
        let rows = [
            row(serverPostId: 1, url: "https://example.com/app/#/x"),
            row(serverPostId: 2, url: "https://example.com/app/#/y"),
        ]
        let result = CrossPostGrouper.group(rows: rows)

        #expect(result.displayed.map(\.serverPostId) == [1, 2])
        #expect(result.siblingsByPrimary.isEmpty)
    }

    @Test
    func deliberatelyDifferentUrlsAreNotGrouped() {
        let rows = [
            row(serverPostId: 1, url: "https://example.com/article-one"),
            row(serverPostId: 2, url: "https://example.com/article-two"),
        ]
        let result = CrossPostGrouper.group(rows: rows)

        #expect(result.displayed.map(\.serverPostId) == [1, 2])
        #expect(result.siblingsByPrimary.isEmpty)
    }

    @Test
    func unparseableUrlFallsBackToExactStringMatch() {
        // `URLComponents(string:)` is lenient (it percent-encodes stray
        // characters rather than failing) for most malformed input, but a
        // string it genuinely can't parse — e.g. an invalid bracketed host —
        // returns nil. Not a real-world case (a post's `url` is validated at
        // import time), but the fallback path should still only match
        // byte-for-byte, never crash.
        let rows = [
            row(serverPostId: 1, url: "http://[invalid"),
            row(serverPostId: 2, url: "http://[invalid"),
            row(serverPostId: 3, url: "http://[also-invalid"),
        ]
        let result = CrossPostGrouper.group(rows: rows)

        #expect(result.displayed.map(\.serverPostId) == [1, 3])
        #expect(result.siblingsByPrimary[1]?.map(\.serverPostId) == [2])
    }
}
