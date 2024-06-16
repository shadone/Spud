//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog
import UIKit

private let logger = Logger.app

extension UIFont {
    static func scaledFont(
        fontName: String,
        style textStyle: UIFont.TextStyle,
        relativeSize: CGFloat
    ) -> UIFont {
        let size = UIFont.systemFontSize + relativeSize
        let font: UIFont = {
            guard
                let font = UIFont(name: fontName, size: size)
            else {
                logger.assertionFailure("Failed to find font '\(fontName)'")
                return .systemFont(ofSize: size)
            }
            return font
        }()
        return UIFontMetrics(forTextStyle: textStyle)
            .scaledFont(for: font)
    }

    static func scaledSystemFont(
        style textStyle: UIFont.TextStyle,
        relativeSize: CGFloat,
        weight: UIFont.Weight = .regular
    ) -> UIFont {
        let font = UIFont.systemFont(
            ofSize: UIFont.systemFontSize + relativeSize,
            weight: weight
        )
        return UIFontMetrics(forTextStyle: textStyle)
            .scaledFont(for: font)
    }

    static func scaledMonospaceDigitSystemFont(
        style textStyle: UIFont.TextStyle,
        relativeSize: CGFloat,
        weight: UIFont.Weight = .regular
    ) -> UIFont {
        let font = UIFont.monospacedSystemFont(
            ofSize: UIFont.systemFontSize + relativeSize,
            weight: weight
        )
        return UIFontMetrics(forTextStyle: textStyle)
            .scaledFont(for: font)
    }
}
