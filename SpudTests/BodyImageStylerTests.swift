//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Down
import UIKit
import XCTest
@testable import Spud

/// Verifies the render layer for inline images: `BodyImageStyler` turns a
/// markdown image into a `BodyImageAttachment` carrying the URL/alt text, stamped
/// with a tappable `.link`, instead of Down's default (which drops the image).
final class BodyImageStylerTests: XCTestCase {
    private func render(_ markdown: String) -> NSAttributedString {
        MarkdownRenderer().attributedString(
            markdown: markdown,
            key: markdown,
            makeStyler: { BodyImageStyler(configuration: PostDetailAppearance.bodyStylerConfiguration(for: 0)) }
        )
    }

    private func attachment(in attributed: NSAttributedString) -> BodyImageAttachment? {
        var found: BodyImageAttachment?
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
            if let attachment = value as? BodyImageAttachment {
                found = attachment
                stop.pointee = true
            }
        }
        return found
    }

    func test_imageMarkdown_producesAttachmentWithURLAndAlt() {
        let result = render("before ![a cat](https://example.com/cat.png) after")

        let attachment = attachment(in: result)
        XCTAssertNotNil(attachment, "a markdown image must become a BodyImageAttachment")
        XCTAssertEqual(attachment?.imageURL.absoluteString, "https://example.com/cat.png")
        XCTAssertEqual(attachment?.altText, "a cat")
    }

    func test_imageWithoutAltText_stillProducesAttachment() {
        // The reported case: an uploaded image with no alt text. Down would render
        // nothing here; we must still get an attachment so the image shows.
        let result = render("![](https://example.com/pic.jpg)")

        let attachment = attachment(in: result)
        XCTAssertNotNil(attachment, "an image with empty alt text must still produce an attachment")
        XCTAssertEqual(attachment?.imageURL.absoluteString, "https://example.com/pic.jpg")
        XCTAssertNil(attachment?.altText, "empty alt text is normalised to nil")
    }

    func test_imageAttachmentRange_carriesImageLinkForTapRouting() {
        let result = render("![x](https://example.com/x.png)")

        var linkURL: URL?
        result.enumerateAttribute(.link, in: NSRange(location: 0, length: result.length)) { value, _, stop in
            if let url = value as? URL {
                linkURL = url
                stop.pointee = true
            }
        }
        XCTAssertEqual(
            linkURL?.absoluteString,
            "https://example.com/x.png",
            "the attachment must be tappable so it opens the fullscreen viewer"
        )
    }

    func test_textAroundImage_isPreserved() {
        let result = render("look ![](https://example.com/p.png) here")
        XCTAssertTrue(result.string.contains("look"))
        XCTAssertTrue(result.string.contains("here"))
    }
}
