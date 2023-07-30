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
        numberOfVotesOrScore value: Int64,
        voteStatus: VoteStatus,
        attributes: [NSAttributedString.Key: Any],
        appearance: GeneralAppearance
    ) -> NSAttributedString {
        let icon: UIImage
        var attributes = attributes

        switch voteStatus {
        case .up:
            icon = UIImage(systemName: "arrow.up")!
            attributes[.foregroundColor] = appearance.upvoteButtonActiveColor

        case .neutral:
            icon = UIImage(systemName: "arrow.up")!

        case .down:
            icon = UIImage(systemName: "arrow.down")!
            attributes[.foregroundColor] = appearance.downvoteButtonActiveColor
        }

        return Self.attributedString(
            icon,
            UpvotesFormatter.string(from: value),
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
        return Self.attributedString(
            UIImage(systemName: "clock")!,
            "\(timestamp.relativeString)",
            attributes: attributes
        )
    }
}
