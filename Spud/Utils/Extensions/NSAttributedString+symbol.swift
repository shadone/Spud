//
// Copyright (c) 2021-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

extension NSAttributedString {
    static func symbol(
        from sourceImage: UIImage,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let attachment = NSTextAttachment()

        let image: UIImage
        // TODO: do we need this? It used to be needed for custom images in AppKit.
//        if let color = attributes[.strokeColor] as? UIColor {
//            image = sourceImage.tinted(with: color)
//        } else if let color = attributes[.foregroundColor] as? UIColor {
//            image = sourceImage.tinted(with: color)
//        } else {
//            image = sourceImage
//        }
        image = sourceImage

        attachment.image = image

        if let font = attributes[.font] as? UIFont {
            let aspectRatio = image.size.width / image.size.height

            let yOffset = font.descender / 2

            let height = font.capHeight + abs(yOffset) * 2
            let width = height * aspectRatio

            attachment.bounds = CGRect(x: 0, y: yOffset, width: width, height: height)
        }

        let string = NSMutableAttributedString(attachment: attachment)
        string.addAttributes(attributes, range: NSRange(location: 0, length: string.length))
        return string
    }
}
