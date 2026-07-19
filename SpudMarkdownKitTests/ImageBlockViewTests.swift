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

    @Test
    func retryAfterFailedLoadReloadsImage() async throws {
        let url = try #require(URL(string: "https://example.com/a.jpg"))
        let counter = LoaderCallCounter()
        let view = ImageBlockView(
            image: MarkdownImage(url: url, altText: "alt"),
            context: MarkdownContext(kind: .post),
            onTapImage: nil,
            onOpenInBrowser: nil,
            onContentSizeChange: nil,
            loader: { _ in
                counter.count += 1
                // Fail the first attempt (a transient error), succeed on retry.
                return counter.count == 1 ? nil : UIImage()
            }
        )

        await poll { button(titled: "Retry", in: view) != nil }
        let retry = try #require(
            button(titled: "Retry", in: view),
            "the failed plate must offer a Retry button"
        )
        #expect(
            button(titled: "Open in browser", in: view) != nil,
            "Retry must sit alongside Open in browser, not replace it"
        )

        retry.sendActions(for: .touchUpInside)
        await poll { view.isAccessibilityElement }
        #expect(counter.count == 2, "tapping Retry must re-invoke the loader")
        #expect(view.isAccessibilityElement, "the retried load must reach the loaded state")
        #expect(
            button(titled: "Retry", in: view) == nil,
            "the loaded state must not keep the Retry button"
        )
    }

    /// Mutable call counter for a loader closure to capture (an escaping closure
    /// can't capture a mutable local under strict concurrency).
    @MainActor
    private final class LoaderCallCounter {
        var count = 0
    }

    /// Recursively finds the first `UIButton` under `root` carrying `title`.
    private func button(titled title: String, in root: UIView) -> UIButton? {
        for subview in root.subviews {
            if let button = subview as? UIButton, button.title(for: .normal) == title {
                return button
            }
            if let found = button(titled: title, in: subview) {
                return found
            }
        }
        return nil
    }

    /// Bounded poll for a condition published by the fire-and-forget image-load
    /// `Task`. Returns as soon as the predicate holds, or after `timeout`.
    private func poll(
        timeout: Duration = .seconds(2),
        until predicate: @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
