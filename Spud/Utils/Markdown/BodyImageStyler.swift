//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Down
import UIKit

/// A `DownStyler` that renders markdown images as inline `BodyImageAttachment`s
/// instead of dropping them.
///
/// Down's default `style(image:)` only styles the alt-text children as a generic
/// link and discards the image URL, so an image with no alt text renders as
/// nothing. This subclass replaces the image node's content with a single
/// attachment character backed by a `BodyImageAttachment`, and stamps the image
/// URL as a `.link` over it so a tap routes through the existing body-link
/// handling (which opens the fullscreen media viewer for image URLs).
final class BodyImageStyler: DownStyler {
    override func style(image str: NSMutableAttributedString, title: String?, url: String?) {
        guard
            let urlString = url,
            let imageURL = URL(string: urlString)
        else {
            // Not a usable URL — fall back to Down's alt-text-as-link behaviour.
            super.style(image: str, title: title, url: url)
            return
        }

        // Prefer the rendered alt text; fall back to the markdown title attribute.
        let alt = str.string.isEmpty ? title : str.string

        let attachment = BodyImageAttachment(imageURL: imageURL, altText: alt)
        let attachmentString = NSMutableAttributedString(attachment: attachment)
        attachmentString.addAttribute(
            .link,
            value: imageURL,
            range: NSRange(location: 0, length: attachmentString.length)
        )
        str.setAttributedString(attachmentString)
    }
}
