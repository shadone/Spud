//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
import UIKit
@testable import SpudMarkdownKit

@MainActor
struct ImageBlockViewTests {
    private func makeView(
        altText: String?,
        onTapImage: ((URL, String?, CGRect) -> Void)? = nil
    ) throws -> (ImageBlockView, URL) {
        let url = try #require(URL(string: "https://example.com/a.jpg"))
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

    @Test
    func loadedImageIsActivatableAccessibilityElement() throws {
        var tapped: URL?
        let (view, url) = try makeView(altText: "A grey cat") { tappedURL, _, _ in tapped = tappedURL }
        view.apply(state: .loaded(UIImage()))

        #expect(view.isAccessibilityElement)
        #expect(view.accessibilityLabel == "A grey cat")
        #expect(view.accessibilityHint == "Tap to zoom")
        #expect(view.accessibilityTraits.contains(.image))
        #expect(view.accessibilityTraits.contains(.button))

        #expect(view.accessibilityActivate())
        #expect(tapped == url)
    }

    @Test
    func loadedImageWithoutAltUsesGenericLabel() throws {
        let (view, _) = try makeView(altText: nil)
        view.apply(state: .loaded(UIImage()))
        #expect(view.accessibilityLabel == "Image")
    }

    @Test
    func failedImageIsNotAnAccessibilityElement() throws {
        let (view, _) = try makeView(altText: "alt")
        view.apply(state: .failed)
        #expect(!view.isAccessibilityElement)
    }

    @Test
    func loadingImageIsNotActivatable() throws {
        let (view, _) = try makeView(altText: "alt")
        view.apply(state: .loading)
        #expect(!view.isAccessibilityElement)
        #expect(!view.accessibilityActivate())
    }
}
