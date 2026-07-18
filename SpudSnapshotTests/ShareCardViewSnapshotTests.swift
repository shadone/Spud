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

    // MARK: - Theme independence (no reference image)

    func test_fixedPalette_isThemeIndependent_lightAndDarkTraitsAreByteIdentical() throws {
        // The card's colors come from ``ShareCardPalette`` (a fixed two-surface
        // palette keyed on `options.appearance`), never the trait environment.
        // So the SAME card config rendered under a light vs a dark
        // `UITraitCollection` must produce byte-identical PNGs — locking the
        // fixed-palette guarantee against someone reintroducing a dynamic color
        // (e.g. `.label`), which would resolve differently per trait and fail
        // here. A pure in-test byte comparison: no `assertSnapshot`, no
        // reference image.
        let options = options(.light)
        let lightData = try renderPNGData(options: options, style: .light)
        let darkData = try renderPNGData(options: options, style: .dark)
        XCTAssertEqual(lightData, darkData)
    }

    /// Renders the post card to PNG bytes under a forced interface style: both
    /// the view subtree (`overrideUserInterfaceStyle`) and the ambient
    /// `UITraitCollection.current` (via `performAsCurrent`) are pinned to
    /// `style`, so any trait-dependent color resolution would diverge between
    /// the two calls.
    private func renderPNGData(options: ShareCardOptions, style: UIUserInterfaceStyle) throws -> Data {
        let card = ShareCardView(
            content: postContent(),
            options: options,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(identifier: "GMT")!
        )
        card.overrideUserInterfaceStyle = style
        let size = ShareCardSnapshotSupport.fit(card)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 2
        format.opaque = false
        var image: UIImage?
        ShareCardSnapshotSupport.traits(style).performAsCurrent {
            image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                card.layer.render(in: context.cgContext)
            }
        }
        return try XCTUnwrap(image?.pngData())
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

    private func solidImage(_ color: UIColor, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
