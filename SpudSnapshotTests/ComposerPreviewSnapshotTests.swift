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

/// A synchronous stub image service so the composer preview's inline image
/// renders deterministically (no network).
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

/// Verifies the composer's Preview tab renders a markdown draft through
/// `MarkdownBodyView`, including an inline image.
@MainActor
final class ComposerPreviewSnapshotTests: XCTestCase {
    private let width: CGFloat = 390

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
        ])
    }

    private func solidImage(_ size: CGSize, color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    func test_preview_rendersDraft() {
        let editor = MarkdownEditorView()
        editor.imageService = StubImageService(
            image: solidImage(CGSize(width: 300, height: 150), color: .systemIndigo)
        )
        editor.text = """
            # Draft heading

            Some **bold** body text with a [link](https://example.com).

            ![pic](https://example.com/pic.png)
            """
        editor.frame = CGRect(x: 0, y: 0, width: width, height: 600)
        editor.setMode(.preview)

        // Let the synchronous stub image load and the body re-measure.
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if editor.subviews.contains(where: { !$0.isHidden }) { break }
        }
        editor.layoutIfNeeded()

        assertSnapshot(
            matching: editor,
            as: .image(size: CGSize(width: width, height: 600), traits: traits(.light))
        )
    }
}
