//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import XCTest
@testable import Spud

/// `BodyTextView` is an accessibility container: every tappable link and every
/// inline image is surfaced as its own focusable element (the image carrying its
/// markdown alt text), so VoiceOver can land on and announce each one instead of
/// the body reading as one opaque blob. Plain text keeps the default text-view
/// behaviour.
@MainActor
final class BodyTextViewAccessibilityTests: XCTestCase {
    private func body(_ markdown: String) -> NSAttributedString {
        MarkdownRenderer().imageBody(markdown: markdown, textSizeAdjustment: 0)
    }

    private func elements(for markdown: String) -> [UIAccessibilityElement] {
        let textView = BodyTextView()
        textView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        textView.attributedText = body(markdown)
        textView.layoutIfNeeded()
        return (textView.accessibilityElements as? [UIAccessibilityElement]) ?? []
    }

    func test_inlineImage_isExposedWithAltText() {
        let els = elements(for: "![a friendly cat](https://example.com/cat.png)")
        let image = els.first { $0.accessibilityTraits.contains(.image) }
        XCTAssertEqual(image?.accessibilityLabel, "a friendly cat")
    }

    func test_inlineImageWithoutAltText_isStillExposedAsImage() {
        let els = elements(for: "![](https://example.com/cat.png)")
        let image = els.first { $0.accessibilityTraits.contains(.image) }
        XCTAssertNotNil(image, "an image with no alt text must still be announced as an image")
    }

    func test_link_isExposedWithDestination() {
        let els = elements(for: "see the [docs](https://example.com/docs) page")
        let link = els.first { $0.accessibilityTraits.contains(.link) }
        XCTAssertEqual(link?.accessibilityLabel, "docs")
        XCTAssertEqual(link?.accessibilityValue, "https://example.com/docs")
    }

    func test_plainText_keepsDefaultTextViewAccessibility() {
        let textView = BodyTextView()
        textView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        textView.attributedText = body("just some words, nothing to land on")
        XCTAssertNil(
            textView.accessibilityElements,
            "a body with no links or images must not become a container"
        )
    }
}
