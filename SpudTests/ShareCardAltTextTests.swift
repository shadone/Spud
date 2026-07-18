//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud

struct ShareCardAltTextTests {
    private let published = Date(timeIntervalSince1970: 1_784_000_000) // an arbitrary fixed instant

    /// Mirrors `ShareCardAltText`'s own date formatting so the expected string
    /// is correct under whatever locale/timezone the test happens to run in,
    /// instead of hard-coding a locale-specific string like "Jul 12, 2026".
    private func mediumDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func postSummary(
        title: String = "Cool title",
        communityHandle: String = "c/linux@lemmy.ml",
        score: Int64 = 3400,
        commentCount: Int64 = 612
    ) -> ShareCardContent.PostSummary {
        ShareCardContent.PostSummary(
            title: title,
            bodyPlain: nil,
            communityName: "linux",
            communityHandle: communityHandle,
            communityIconUrl: nil,
            creatorHandle: "u/alice@lemmy.ml",
            score: score,
            commentCount: commentCount,
            published: published,
            permalink: URL(string: "https://lemmy.ml/post/1")!,
            mediaUrl: nil,
            mediaAspectIsWide: false,
            isNsfw: false
        )
    }

    @Test
    func post_matchesDesignSpecShape() {
        let content = ShareCardContent(post: postSummary(), chain: [], kind: .post)
        let altText = ShareCardAltText.make(content: content, options: ShareCardOptions())

        let expected = "Lemmy post in c/linux@lemmy.ml: \"Cool title\", 3.4K points, 612 comments, " +
            "\(mediumDateString(published)). Shared via Spud."
        #expect(altText == expected)
    }

    @Test
    func comment_matchesDesignSpecShape() throws {
        let destination = try ShareCardContent.ChainItem(
            authorHandle: "u/name@instance",
            score: 52,
            bodyPlain: "a short comment body",
            published: published,
            isDestination: true,
            permalink: #require(URL(string: "https://instance/comment/1"))
        )
        let content = ShareCardContent(
            post: postSummary(communityHandle: "c/…"),
            chain: [destination],
            kind: .comment
        )
        let altText = ShareCardAltText.make(content: content, options: ShareCardOptions())

        let expected = "Comment by u/name@instance in c/…: \"a short comment body\", 52 points, " +
            "\(mediumDateString(published)). Shared via Spud."
        #expect(altText == expected)
    }

    @Test
    func comment_withoutPostContext_omitsTheInCommunityClause() throws {
        let destination = try ShareCardContent.ChainItem(
            authorHandle: "u/name@instance",
            score: 5,
            bodyPlain: "hi",
            published: published,
            isDestination: true,
            permalink: #require(URL(string: "https://instance/comment/1"))
        )
        let content = ShareCardContent(post: nil, chain: [destination], kind: .comment)
        let altText = ShareCardAltText.make(content: content, options: ShareCardOptions())

        #expect(altText.hasPrefix("Comment by u/name@instance: "))
        #expect(!altText.contains(" in "))
    }

    @Test
    func comment_redactIdentities_omitsAuthorHandle() throws {
        var options = ShareCardOptions()
        options.redactIdentities = true

        let destination = try ShareCardContent.ChainItem(
            authorHandle: "u/name@instance",
            score: 52,
            bodyPlain: "a short comment body",
            published: published,
            isDestination: true,
            permalink: #require(URL(string: "https://instance/comment/1"))
        )
        let content = ShareCardContent(
            post: postSummary(communityHandle: "c/…"),
            chain: [destination],
            kind: .comment
        )
        let altText = ShareCardAltText.make(content: content, options: options)

        #expect(!altText.contains("u/name@instance"))
        // The community is never redacted.
        #expect(altText.contains("c/…"))
        #expect(altText.hasPrefix("Comment in c/…: "))
    }

    @Test
    func comment_longBody_isTruncatedWithEllipsis() throws {
        let longBody = String(repeating: "word ", count: 40).trimmingCharacters(in: .whitespaces)
        let destination = try ShareCardContent.ChainItem(
            authorHandle: "u/name@instance",
            score: 1,
            bodyPlain: longBody,
            published: published,
            isDestination: true,
            permalink: #require(URL(string: "https://instance/comment/1"))
        )
        let content = ShareCardContent(post: nil, chain: [destination], kind: .comment)
        let altText = ShareCardAltText.make(content: content, options: ShareCardOptions())

        #expect(altText.contains("\u{2026}")) // the ellipsis character
        #expect(!altText.contains(longBody))
    }
}
