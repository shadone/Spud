//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Snapshots of ``ShareChainCardView`` — the fixed-metric, fixed-palette
/// comment-share card (shared comment + ancestor chain).
///
/// Like ``ShareCardViewSnapshotTests`` the card is theme-independent (colors from
/// ``ShareCardPalette``, driven by `options.appearance`) and ignores Dynamic
/// Type (fixed internal fonts), so no trait plumbing beyond a pinned display
/// scale is needed. The destination's absolute timestamp is made deterministic
/// by injecting a fixed `Date` plus an `en_US_POSIX`/`GMT` locale/time-zone seam.
///
/// Matrix (from the plan): chain depth 0 (destination only) / 3 / deep-elided;
/// the post header on and off; dark; and redacted — the redacted case asserts
/// the guardrail that the shared comment's timestamp and the footer permalink
/// still render even with every author masked.
@MainActor
final class ShareChainCardViewSnapshotTests: XCTestCase {
    /// A fixed instant (2026-07-12 16:03 GMT), formatting to
    /// "Jul 12, 2026 at 4:03 PM" under the injected `en_US_POSIX`/`GMT` seam.
    private let fixedDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 12
        components.hour = 16
        components.minute = 3
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar.date(from: components)!
    }()

    // MARK: - Tests

    func test_depth0_destinationOnly_light() {
        // Depth 0: no ancestors render, only the shared comment (plus header).
        assert(
            content: chainContent(ancestorCount: 3),
            options: options(.light, chainDepth: 0)
        )
    }

    func test_depth3_light() {
        assert(
            content: chainContent(ancestorCount: 3),
            options: options(.light, chainDepth: 3)
        )
    }

    func test_deepElided_light() {
        // Six ancestors at full depth: elides to top-2 + "2 more replies" + bottom-2.
        assert(
            content: chainContent(ancestorCount: 6),
            options: options(.light, chainDepth: 8)
        )
    }

    func test_includePostOff_light() {
        assert(
            content: chainContent(ancestorCount: 3),
            options: options(.light, chainDepth: 3, includePostInChain: false)
        )
    }

    func test_depth3_dark() {
        assert(
            content: chainContent(ancestorCount: 3),
            options: options(.dark, chainDepth: 3)
        )
    }

    func test_redacted_light() {
        // Guardrail: with identities redacted, the shared comment's timestamp
        // and the footer permalink must still render.
        assert(
            content: chainContent(ancestorCount: 3),
            options: options(.light, chainDepth: 3, redactIdentities: true)
        )
    }

    // MARK: - Fixtures

    private func chainContent(ancestorCount: Int) -> ShareCardContent {
        let post = ShareCardContent.PostSummary(
            title: "Understanding Auto Layout from first principles",
            bodyPlain: "A short lead paragraph that introduces the post.",
            communityName: "Linux",
            communityHandle: "c/linux@lemmy.ml",
            communityIconUrl: nil,
            creatorHandle: "u/torvalds@lemmy.ml",
            score: 3402,
            commentCount: 612,
            published: fixedDate,
            permalink: URL(string: "https://lemmy.ml/post/1284920")!,
            mediaUrl: nil,
            mediaAspectIsWide: false,
            isNsfw: false
        )
        let ancestors = (1...ancestorCount).map { ancestor($0) }
        let destination = ShareCardContent.ChainItem(
            authorHandle: "u/ada@lemmy.ml",
            score: 128,
            bodyPlain: "This is exactly the mental model I was missing — describing relationships "
                + "instead of positions makes the whole thing click.",
            published: fixedDate,
            isDestination: true,
            permalink: URL(string: "https://lemmy.ml/comment/994210")!
        )
        return ShareCardContent(post: post, chain: ancestors + [destination], kind: .comment)
    }

    private func ancestor(_ id: Int) -> ShareCardContent.ChainItem {
        ShareCardContent.ChainItem(
            authorHandle: "u/user\(id)@lemmy.ml",
            score: Int64(id * 7),
            bodyPlain: "Ancestor \(id): a reply adding a bit of context to the thread above the shared comment.",
            published: nil,
            isDestination: false,
            permalink: nil
        )
    }

    private func options(
        _ appearance: ShareCardOptions.Appearance,
        chainDepth: Int,
        includePostInChain: Bool = true,
        redactIdentities: Bool = false,
        showViaSpudMark: Bool = true
    ) -> ShareCardOptions {
        ShareCardOptions(
            appearance: appearance,
            redactIdentities: redactIdentities,
            chainDepth: chainDepth,
            includePostInChain: includePostInChain,
            showViaSpudMark: showViaSpudMark
        )
    }

    // MARK: - Rendering

    private func assert(
        content: ShareCardContent,
        options: ShareCardOptions,
        testName: String = #function,
        line: UInt = #line
    ) {
        let card = ShareChainCardView(
            content: content,
            options: options,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(identifier: "GMT")!
        )
        let size = ShareCardSnapshotSupport.fit(card)
        let style: UIUserInterfaceStyle = options.appearance == .dark ? .dark : .light
        assertSnapshot(
            matching: card,
            as: .image(size: size, traits: ShareCardSnapshotSupport.traits(style)),
            file: #file,
            testName: testName,
            line: line
        )
    }
}
