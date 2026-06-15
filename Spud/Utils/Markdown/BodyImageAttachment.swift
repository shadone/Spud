//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A text attachment that stands in for a markdown image (`![alt](url)`) inside a
/// rendered body. It carries the image's URL and alt text; `BodyTextView` loads
/// the image asynchronously and sets `image` / `aspectRatio` once it arrives,
/// then re-lays-out so the run reflows to the real size.
///
/// `MarkdownRenderer` caches the rendered body, so a cached attachment must not be
/// mutated by display. `BodyTextView` substitutes a fresh ``displayCopy()`` before
/// assigning the text, so two text views never race on one instance and the cache
/// stays free of per-display state (the loaded `image`, `aspectRatio`).
final class BodyImageAttachment: NSTextAttachment {
    /// The source image URL parsed from the markdown.
    let imageURL: URL

    /// The markdown alt text, used for the fullscreen viewer caption and
    /// VoiceOver. Empty alt text is normalised to nil.
    let altText: String?

    /// The loaded image's aspect ratio (width / height), known after load. While
    /// nil, the attachment reserves a placeholder box so the row height is stable.
    var aspectRatio: CGFloat?

    /// The maximum height an inline image may occupy, so a tall image does not
    /// dominate the comment. Set by the host text view at display time.
    var maxDisplayHeight: CGFloat = 320

    /// Reserved aspect (width / height) used before the real image loads.
    private static let placeholderAspect: CGFloat = 4.0 / 3.0

    init(imageURL: URL, altText: String?) {
        self.imageURL = imageURL
        let trimmed = altText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.altText = (trimmed?.isEmpty ?? true) ? nil : trimmed
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A fresh copy carrying no loaded state. Used so a cached, shared attachment
    /// is never mutated and two text views never race on one instance.
    func displayCopy() -> BodyImageAttachment {
        let copy = BodyImageAttachment(imageURL: imageURL, altText: altText)
        copy.maxDisplayHeight = maxDisplayHeight
        return copy
    }

    /// The box the attachment occupies for a given available text width: the full
    /// width at the image's aspect ratio, capped to `maxDisplayHeight` (shrinking
    /// the width to preserve aspect when capped).
    private func bounds(forAvailableWidth available: CGFloat) -> CGRect {
        let width = max(1, available)
        let aspect = aspectRatio ?? Self.placeholderAspect
        var size = CGSize(width: width, height: (width / aspect).rounded())
        if size.height > maxDisplayHeight {
            size = CGSize(width: (maxDisplayHeight * aspect).rounded(), height: maxDisplayHeight)
        }
        return CGRect(origin: .zero, size: size)
    }

    /// TextKit 2 (UITextView on iOS 16+) asks via the NSTextAttachmentLayout method.
    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let available = proposedLineFragment.width > 0
            ? proposedLineFragment.width
            : (textContainer?.size.width ?? proposedLineFragment.width)
        return bounds(forAvailableWidth: available)
    }

    /// TextKit 1 fallback (kept so the attachment sizes correctly if a host text
    /// view ever falls back to the legacy layout manager).
    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let available = lineFrag.width > 0
            ? lineFrag.width
            : (textContainer?.size.width ?? lineFrag.width)
        return bounds(forAvailableWidth: available)
    }
}
