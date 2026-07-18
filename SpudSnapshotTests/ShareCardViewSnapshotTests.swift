//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Snapshots of ``ShareCardView`` — the fixed-metric, fixed-palette post card.
///
/// The card is theme-independent (its colors come from ``ShareCardPalette``,
/// driven by `options.appearance`, never the trait environment) and ignores
/// Dynamic Type (fixed internal fonts), so no trait plumbing beyond a pinned
/// display scale is needed. Determinism of the absolute timestamp is achieved
/// by injecting a fixed `Date` plus an `en_US_POSIX`/`GMT` locale/time-zone
/// seam so the formatted string never depends on the running machine.
///
/// Guardrails exercised here: the permalink and the absolute timestamp render
/// in EVERY configuration (see `test_statsHidden_*` and `test_viaSpudMarkOff_*`)
/// — only the "via Spud" mark toggles.
@MainActor
final class ShareCardViewSnapshotTests: XCTestCase {
    private let width: CGFloat = 372

    /// A fixed instant (2026-07-12 16:03 GMT). Combined with the card's
    /// injected `en_US_POSIX`/`GMT` seam it always formats to
    /// "Jul 12, 2026 at 4:03 PM".
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

    func test_fullConfig_light() {
        assert(content: postContent(), options: options(.light))
    }

    func test_fullConfig_dark() {
        assert(content: postContent(), options: options(.dark))
    }

    func test_bodyFull_light() {
        assert(
            content: postContent(body: longBody),
            options: options(.light, bodyTreatment: .full)
        )
    }

    func test_bodyTruncate_light() {
        assert(
            content: postContent(body: longBody),
            options: options(.light, bodyTreatment: .truncate)
        )
    }

    func test_bodyTitleOnly_light() {
        assert(
            content: postContent(body: longBody),
            options: options(.light, bodyTreatment: .titleOnly)
        )
    }

    func test_media_light() {
        assert(
            content: postContent(mediaUrl: mediaURL),
            options: options(.light),
            media: solidImage(.init(red: 0.20, green: 0.45, blue: 0.72, alpha: 1), size: CGSize(width: 400, height: 300))
        )
    }

    func test_mediaWide_light() {
        assert(
            content: postContent(mediaUrl: mediaURL, mediaAspectIsWide: true),
            options: options(.light),
            media: solidImage(.init(red: 0.72, green: 0.36, blue: 0.20, alpha: 1), size: CGSize(width: 800, height: 300))
        )
    }

    func test_mediaLoading_light() {
        // A media URL but NO injected image: the media block renders its
        // deterministic loading state (flat chip fill + "Loading media…"). The
        // moving shimmer highlight is parked off the left edge in its model
        // state, so an off-screen render captures a stable first frame.
        assert(
            content: postContent(mediaUrl: mediaURL),
            options: options(.light)
        )
    }

    func test_nsfwSpoilered_light() {
        assert(
            content: postContent(mediaUrl: mediaURL, isNsfw: true),
            options: options(.light),
            media: solidImage(.init(red: 0.55, green: 0.20, blue: 0.45, alpha: 1), size: CGSize(width: 400, height: 300))
        )
    }

    func test_redacted_light() {
        assert(
            content: postContent(),
            options: options(.light, redactIdentities: true)
        )
    }

    func test_statsHidden_light() {
        // Guardrail: with stats hidden the absolute timestamp must still render.
        assert(
            content: postContent(),
            options: options(.light, showStats: false)
        )
    }

    func test_viaSpudMarkOff_light() {
        // Guardrail: with the "via Spud" mark off the permalink must still render.
        assert(
            content: postContent(),
            options: options(.light, showViaSpudMark: false)
        )
    }

    // MARK: - Fixtures

    private var mediaURL: URL {
        URL(string: "https://lemmy.ml/pictrs/image/abcdef.png")!
    }

    private let longBody = """
        Auto Layout is a constraint-based layout system that lets you build adaptive \
        interfaces. Rather than positioning views with fixed frames, you describe the \
        relationships between them and the system solves for the final geometry at \
        runtime. This makes a single layout work across every screen size, orientation, \
        and Dynamic Type setting without a separate design for each. The trade-off is a \
        steeper mental model up front, but the payoff is interfaces that stay correct as \
        content and context change underneath them.
        """

    private func postContent(
        body: String? = "A short lead paragraph that introduces the post.",
        mediaUrl: URL? = nil,
        mediaAspectIsWide: Bool = false,
        isNsfw: Bool = false
    ) -> ShareCardContent {
        let summary = ShareCardContent.PostSummary(
            title: "Understanding Auto Layout from first principles",
            bodyPlain: body,
            communityName: "Linux",
            communityHandle: "c/linux@lemmy.ml",
            communityIconUrl: nil,
            creatorHandle: "u/torvalds@lemmy.ml",
            score: 3402,
            commentCount: 612,
            published: fixedDate,
            permalink: URL(string: "https://lemmy.ml/post/1284920")!,
            mediaUrl: mediaUrl,
            mediaAspectIsWide: mediaAspectIsWide,
            isNsfw: isNsfw
        )
        return ShareCardContent(post: summary, chain: [], kind: .post)
    }

    private func options(
        _ appearance: ShareCardOptions.Appearance,
        showStats: Bool = true,
        bodyTreatment: ShareCardOptions.BodyTreatment = .truncate,
        redactIdentities: Bool = false,
        showViaSpudMark: Bool = true
    ) -> ShareCardOptions {
        ShareCardOptions(
            appearance: appearance,
            showStats: showStats,
            bodyTreatment: bodyTreatment,
            redactIdentities: redactIdentities,
            showViaSpudMark: showViaSpudMark
        )
    }

    // MARK: - Rendering

    private func assert(
        content: ShareCardContent,
        options: ShareCardOptions,
        media: UIImage? = nil,
        testName: String = #function,
        line: UInt = #line
    ) {
        let card = ShareCardView(
            content: content,
            options: options,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(identifier: "GMT")!
        )
        if let media {
            card.setMediaImage(media)
        }
        let size = fit(card)
        let style: UIUserInterfaceStyle = options.appearance == .dark ? .dark : .light
        assertSnapshot(
            matching: card,
            as: .image(size: size, traits: traits(style)),
            file: #file,
            testName: testName,
            line: line
        )
    }

    private func fit(_ view: ShareCardView) -> CGSize {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        let height = view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let size = CGSize(width: width, height: height)
        view.frame = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()
        return size
    }

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
        ])
    }

    private func solidImage(_ color: UIColor, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
