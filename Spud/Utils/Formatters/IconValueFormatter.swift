//
// Copyright (c) 2021-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

struct IconValueFormatter {
    static func attributedString(
        _ image: UIImage,
        _ value: String,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let icon = NSAttributedString.symbol(from: image, attributes: attributes)
        let nbsp = NSAttributedString(string: "\u{00a0}")
        let value = NSAttributedString(string: value, attributes: attributes)

        return [
            icon,
            nbsp,
            value,
        ].joined()
    }

    static func attributedString(
        numberOfUpvotes: Int64,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        return Self.attributedString(
            UIImage(systemName: "arrow.up")!,
            UpvotesFormatter.string(from: numberOfUpvotes),
            attributes: attributes
        )
    }

    static func attributedString(
        numberOfComments: Int64,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        return Self.attributedString(
            UIImage(systemName: "text.bubble")!,
            CommentsFormatter.string(from: numberOfComments),
            attributes: attributes
        )
    }

    static func attributedString(
        relativeDate timestamp: Date,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {

        func relativeString(for date: Date) -> String {
            let secs = -date.timeIntervalSinceNow
            let mins = secs / 60
            let hours = mins / 60
            let days = hours / 24
            let months = days / 30 // TODO:
            let years = months / 12

            assert(secs >= 0)

            if secs < 60 {
                return "\(secs.roundedInt)s"
            }
            if mins < 60 {
                return "\(mins.roundedInt)m"
            }
            if hours < 24 {
                return "\(hours.roundedInt)h"
            }
            if days <= 30 {
                return "\(days.roundedInt)d"
            }
            if months < 12 {
                return "\(months.roundedInt)mo"
            }
            return "\(years.roundedInt)y"
        }

        return Self.attributedString(
            UIImage(systemName: "clock")!,
            "\(relativeString(for: timestamp))",
            attributes: attributes
        )
    }
}
