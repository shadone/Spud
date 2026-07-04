//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import UIKit
import XCTest
@testable import Spud

/// An image service that returns a fixed, synchronously-generated image so inline
/// header-image rendering is deterministic (no network, no asset dependency).
private final class StubImageService: ImageServiceType, @unchecked Sendable {
    private let image: UIImage

    init(image: UIImage) {
        self.image = image
    }

    func fetch(_: URL, thumbnail _: URL?) -> AsyncStream<ImageLoadingState> {
        let image = image
        return AsyncStream { continuation in
            continuation.yield(.ready(image))
            continuation.finish()
        }
    }
}

/// Renders a person bio and a community description that each embed an inline
/// markdown image, verifying both header views route through the image-capable
/// `MarkdownBodyView` path and surface the image as a media tile.
@MainActor
final class HeaderInlineImageSnapshotTests: XCTestCase {
    private let width: CGFloat = 390

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }

    private func solidImage(_ size: CGSize, color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Pins `header` to a fixed-width container and drives its run loop until the
    /// content has fully settled, then returns the container and its fitted height
    /// for a deterministic snapshot.
    ///
    /// `loaded` is a per-header content-size signal (`onBodyImageLoaded` /
    /// `onDescriptionHeightChanged`), but it fires on ANY height change — the first
    /// one is plain text layout, BEFORE the inline image finishes rendering — so it
    /// is a necessary gate, not a sufficient one. When `expectsInlineImage` is set we
    /// additionally require the rendered inline image to actually be on screen (the
    /// loaded `ImageBlockView` is the only non-symbol `UIImageView` in these headers)
    /// and the fitted height to hold steady for `requiredStableIterations` consecutive
    /// polls. Fails loudly on timeout so a genuine non-render is a named failure
    /// rather than a silently pre-settled (image-less) snapshot.
    private func fit(
        _ header: UIView,
        expectsInlineImage: Bool = false,
        loaded: () -> Bool
    ) -> (UIView, CGFloat) {
        let container = UIView()
        container.backgroundColor = .systemBackground
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        container.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
        container.layoutIfNeeded()

        func fittedHeight() -> CGFloat {
            container.layoutIfNeeded()
            return container.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
        }

        let requiredStableIterations = 4
        let epsilon: CGFloat = 0.5
        let deadline = Date().addingTimeInterval(2)
        var lastHeight = fittedHeight()
        var stableCount = 0
        var settled = false
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            let height = fittedHeight()
            let imageReady = !expectsInlineImage || containsRenderedImage(header)
            if loaded(), imageReady, abs(height - lastHeight) <= epsilon {
                stableCount += 1
                if stableCount >= requiredStableIterations {
                    settled = true
                    break
                }
            } else {
                stableCount = 0
            }
            lastHeight = height
        }
        if !settled {
            XCTFail("Header content did not settle within 2s")
        }

        return (container, fittedHeight())
    }

    /// Whether the view tree contains a rendered (non-placeholder) inline image.
    /// The loaded `ImageBlockView` hosts a `UIImageView` with the actual bitmap;
    /// every other image in these headers is an SF Symbol (avatar / icon / status
    /// glyphs) or nil, so a non-symbol image uniquely marks the inline image as
    /// on screen.
    private func containsRenderedImage(_ view: UIView) -> Bool {
        if let imageView = view as? UIImageView,
           let image = imageView.image,
           !image.isSymbolImage
        {
            return true
        }
        return view.subviews.contains { containsRenderedImage($0) }
    }

    func test_personBio_withInlineImage_rendersImage() {
        let service = StubImageService(image: solidImage(CGSize(width: 300, height: 150), color: .systemBlue))
        let header = PersonHeaderView()
        header.imageService = service
        var loaded = false
        header.onBodyImageLoaded = { loaded = true }
        header.configure(
            title: "Ada Lovelace",
            handle: "@ada@lemmy.world",
            statsText: "1.2k post · 3.4k comment karma",
            bioMarkdown: "Mathematician and writer.\n\n![portrait](https://example.com/ada.png)\n\nFirst programmer."
        )

        let (view, height) = fit(header, expectsInlineImage: true) { loaded }
        assertSnapshot(
            matching: view,
            as: .image(size: CGSize(width: width, height: height), traits: traits(.light))
        )
    }

    /// A person header in a serious state: a temporary instance ban (banner),
    /// Admin and Bot badges, and a Matrix contact row.
    func test_personHeader_bannedWithBadgesAndMatrix() {
        let header = PersonHeaderView()
        header.configure(
            title: "Ada Lovelace",
            handle: "@ada@lemmy.world",
            statsText: "1.2k post · 3.4k comment karma",
            bioMarkdown: "Mathematician and writer.",
            status: PersonHeaderStatus(
                banText: "Banned · until 3 Mar 2027",
                isDeleted: false,
                isBot: true,
                isAdmin: true,
                matrixUserId: "@ada:matrix.org"
            )
        )

        let (view, height) = fit(header) { true }
        assertSnapshot(
            matching: view,
            as: .image(size: CGSize(width: width, height: height), traits: traits(.light))
        )
    }

    func test_communityDescription_withInlineImage_rendersImage() {
        let service = StubImageService(image: solidImage(CGSize(width: 280, height: 140), color: .systemGreen))
        let header = CommunityHeaderView()
        header.imageService = service
        var loaded = false
        header.onDescriptionHeightChanged = { loaded = true }
        header.configure(
            title: "Technology",
            qualifiedName: "!technology@lemmy.world",
            subscribersText: "42k",
            postsText: "8.1k",
            vitalityText: nil,
            descriptionMarkdown: "A community for tech news.\n\n![banner](https://example.com/tech.png)\n\nBe nice.",
            subscribed: .notSubscribed,
            isNsfw: false,
            blurBanner: false
        )

        let (view, height) = fit(header, expectsInlineImage: true) { loaded }
        assertSnapshot(
            matching: view,
            as: .image(size: CGSize(width: width, height: height), traits: traits(.light))
        )
    }
}
