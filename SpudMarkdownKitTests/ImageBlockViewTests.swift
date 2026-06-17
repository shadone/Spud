//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import XCTest
@testable import SpudMarkdownKit

@MainActor
final class ImageBlockViewTests: XCTestCase {
    private func makeView(
        altText: String?,
        onTapImage: ((URL, String?, CGRect) -> Void)? = nil
    ) throws -> (ImageBlockView, URL) {
        let url = try XCTUnwrap(URL(string: "https://example.com/a.jpg"))
        let view = ImageBlockView(
            image: MarkdownImage(url: url, altText: altText),
            context: MarkdownContext(kind: .post),
            onTapImage: onTapImage,
            onOpenInBrowser: nil,
            onContentSizeChange: nil,
            loader: nil
        )
        return (view, url)
    }

    func test_loadedImageIsActivatableAccessibilityElement() throws {
        var tapped: URL?
        let (view, url) = try makeView(altText: "A grey cat") { tappedURL, _, _ in tapped = tappedURL }
        view.apply(state: .loaded(UIImage()))

        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertEqual(view.accessibilityLabel, "A grey cat")
        XCTAssertEqual(view.accessibilityHint, "Tap to zoom")
        XCTAssertTrue(view.accessibilityTraits.contains(.image))
        XCTAssertTrue(view.accessibilityTraits.contains(.button))

        XCTAssertTrue(view.accessibilityActivate())
        XCTAssertEqual(tapped, url)
    }

    func test_loadedImageWithoutAltUsesGenericLabel() throws {
        let (view, _) = try makeView(altText: nil)
        view.apply(state: .loaded(UIImage()))
        XCTAssertEqual(view.accessibilityLabel, "Image")
    }

    func test_failedImageIsNotAnAccessibilityElement() throws {
        let (view, _) = try makeView(altText: "alt")
        view.apply(state: .failed)
        XCTAssertFalse(view.isAccessibilityElement)
    }

    func test_loadingImageIsNotActivatable() throws {
        let (view, _) = try makeView(altText: "alt")
        view.apply(state: .loading)
        XCTAssertFalse(view.isAccessibilityElement)
        XCTAssertFalse(view.accessibilityActivate())
    }
}
