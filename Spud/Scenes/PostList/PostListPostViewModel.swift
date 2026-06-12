//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUIKit
import UIKit

@MainActor
struct PostListPostViewModel {
    enum Thumbnail: Equatable {
        /// Post points to an image (or has a thumbnail) — load it via ImageService.
        case image(thumbnailUrl: URL)
        /// Text-only post; render the placeholder icon.
        case text
    }

    let title: NSAttributedString
    let subtitle: NSAttributedString
    let thumbnail: Thumbnail
    let isSaved: Bool

    /// Full-resolution image url when the post is an image post, used to open
    /// the full-screen viewer from the list thumbnail. nil for non-image posts.
    let fullImageUrl: URL?

    /// Where the cell should place the thumbnail (or whether to hide it).
    let thumbnailPosition: ThumbnailPosition

    /// Cell margin and inter-element spacing for the active density.
    let density: PostDensity

    init(
        row: PostListRow,
        appearance: AppearanceServiceType,
        postContentDetector: PostContentDetectorServiceType
    ) {
        let density = appearance.postList.postDensity
        self.density = density
        thumbnailPosition = appearance.postList.thumbnailPosition

        // The user's text-scale override plus the active density's own
        // adjustment (compact shaves a point).
        let textSizeAdjustment = appearance.postList.textSizeAdjustment
            + density.relativeFontSizeAdjustment

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.scaledSystemFont(
                style: .title2,
                relativeSize: textSizeAdjustment,
                weight: .medium
            ),
            .foregroundColor: row.isRead ? UIColor.secondaryLabel : UIColor.label,
        ]
        title = NSAttributedString(string: row.title, attributes: titleAttributes)

        let communityAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.scaledSystemFont(
                style: .body,
                relativeSize: -1 + textSizeAdjustment,
                weight: .regular
            ),
            .foregroundColor: UIColor.label,
        ]
        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.scaledSystemFont(
                style: .body,
                relativeSize: -1 + textSizeAdjustment,
                weight: .regular
            ),
            .foregroundColor: UIColor.secondaryLabel,
        ]

        let voteStatus: VoteStatus = {
            switch row.voteStatus {
            case 1: return .up
            case 0: return .down
            default: return .neutral
            }
        }()

        let space = NSAttributedString(string: "  ", attributes: secondaryAttributes)
        var pieces: [NSAttributedString] = [
            NSAttributedString(string: row.communityName, attributes: communityAttributes),
            space,
            IconValueFormatter.attributedString(
                numberOfVotesOrScore: row.score,
                voteStatus: voteStatus,
                attributes: secondaryAttributes,
                appearance: appearance.general
            ),
            space,
            IconValueFormatter.attributedString(
                numberOfComments: row.numberOfComments,
                attributes: secondaryAttributes
            ),
            space,
            IconValueFormatter.attributedString(
                relativeDate: row.published,
                attributes: secondaryAttributes
            ),
        ]

        isSaved = row.isSaved
        if row.isSaved {
            var savedAttributes = secondaryAttributes
            savedAttributes[.foregroundColor] = UIColor.systemYellow
            pieces.append(space)
            pieces.append(NSAttributedString.symbol(
                from: UIImage(systemName: "bookmark.fill")!,
                attributes: savedAttributes
            ))
        }

        // Moderation / content-status badges. A featured (pinned) post gets a
        // green pin; a locked post a yellow lock; a removed-by-mod or
        // deleted-by-author post a red marker.
        for badge in PostStatusBadge.badges(for: row) {
            var attrs = secondaryAttributes
            attrs[.foregroundColor] = badge.color
            pieces.append(space)
            pieces.append(NSAttributedString.symbol(
                from: UIImage(systemName: badge.symbolName)!,
                attributes: attrs
            ))
        }

        subtitle = pieces.joined()

        let url = row.url.flatMap { URL(string: $0) }
        let thumbnailUrl = row.thumbnailUrl.flatMap { URL(string: $0) }
        let contentType = postContentDetector.contentTypeForUrl(
            url: url,
            thumbnailUrl: thumbnailUrl,
            embedTitle: row.urlEmbedTitle,
            embedDescription: row.urlEmbedDescription
        )

        switch contentType {
        case let .image(image):
            thumbnail = .image(thumbnailUrl: image.thumbnailUrl ?? image.imageUrl)
            fullImageUrl = image.imageUrl
        case .externalLink, .textOrEmpty:
            thumbnail = .text
            fullImageUrl = nil
        }
    }
}
