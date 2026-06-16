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

    /// Pins `header` to a fixed-width container, waits for its inline image to
    /// load (signalled via `loaded`) rather than a fixed delay, then returns the
    /// container and its fitted height for a deterministic snapshot.
    private func fit(_ header: UIView, loaded: () -> Bool) -> (UIView, CGFloat) {
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

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, !loaded() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        container.layoutIfNeeded()

        let height = container.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        return (container, height)
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

        let (view, height) = fit(header) { loaded }
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
        header.onBodyImageLoaded = { loaded = true }
        header.configure(
            title: "Technology",
            qualifiedName: "!technology@lemmy.world",
            subscribersText: "42k",
            postsText: "8.1k",
            vitalityText: nil,
            descriptionMarkdown: "A community for tech news.\n\n![banner](https://example.com/tech.png)\n\nBe nice.",
            subscribed: .notSubscribed
        )

        let (view, height) = fit(header) { loaded }
        assertSnapshot(
            matching: view,
            as: .image(size: CGSize(width: width, height: height), traits: traits(.light))
        )
    }
}
