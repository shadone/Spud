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
/// body-image rendering is deterministic (no network, no asset dependency).
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

/// Renders a body containing an inline markdown image through `BodyTextView` so the
/// inline-image layout (placeholder reservation, loaded reflow) is reviewable and
/// regressions are caught.
@MainActor
final class BodyImageSnapshotTests: XCTestCase {
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

    private func body(_ markdown: String) -> NSAttributedString {
        MarkdownRenderer().attributedString(
            markdown: markdown,
            key: markdown,
            makeStyler: { BodyImageStyler(configuration: PostDetailAppearance.bodyStylerConfiguration(for: 0)) }
        )
    }

    /// Builds a `BodyTextView`, wires the stub loader, assigns the body, lets the
    /// async image load settle, and returns the view plus its fitted height.
    private func makeView(
        body attributedText: NSAttributedString,
        imageService: ImageServiceType
    ) -> (UIView, CGFloat) {
        let textView = BodyTextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.imageService = imageService

        let container = UIView()
        container.backgroundColor = .systemBackground
        container.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textView.topAnchor.constraint(equalTo: container.topAnchor),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        container.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
        textView.attributedText = attributedText
        container.layoutIfNeeded()

        // Deterministically wait for the (async) inline image to finish loading
        // rather than a fixed delay, so the snapshot isn't timing-flaky.
        waitForInlineImages(in: textView)
        container.layoutIfNeeded()

        let height = container.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        return (container, height)
    }

    /// Spins the run loop until every inline image attachment has loaded its
    /// image (or a timeout elapses), so the snapshot captures the loaded state
    /// deterministically.
    private func waitForInlineImages(in textView: BodyTextView, timeout: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, pendingImageCount(in: textView) > 0 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func pendingImageCount(in textView: BodyTextView) -> Int {
        guard let attributed = textView.attributedText else { return 0 }
        var pending = 0
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            if let attachment = value as? BodyImageAttachment, attachment.image == nil {
                pending += 1
            }
        }
        return pending
    }

    func test_bodyWithInlineImage_rendersImage() {
        let service = StubImageService(image: solidImage(CGSize(width: 300, height: 150), color: .systemBlue))
        let (view, height) = makeView(
            body: body("Here is a picture:\n\n![a chart](https://example.com/chart.png)\n\nNeat, right?"),
            imageService: service
        )
        assertSnapshot(
            matching: view,
            as: .image(size: CGSize(width: width, height: height), traits: traits(.light))
        )
    }

    func test_bodyWithImageNoAltText_rendersImage() {
        // The reported bug: an image with no alt text. Must still show the image.
        let service = StubImageService(image: solidImage(CGSize(width: 240, height: 240), color: .systemGreen))
        let (view, height) = makeView(
            body: body("look at this\n\n![](https://example.com/pic.jpg)"),
            imageService: service
        )
        assertSnapshot(
            matching: view,
            as: .image(size: CGSize(width: width, height: height), traits: traits(.light))
        )
    }
}
