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
        /// Tapping it opens the full-screen viewer.
        case image(thumbnailUrl: URL)
        /// External-link post that carries an embed image — show it inline (like
        /// the detail view's link preview). Tapping falls through to opening the
        /// post rather than the image viewer.
        case linkImage(thumbnailUrl: URL)
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

    /// A single coherent VoiceOver label for the whole cell: title, community,
    /// score, comments, read and saved state. Replaces the per-glyph reading of
    /// the icon-and-value subtitle, which VoiceOver renders unintelligibly.
    let accessibilityLabel: String

    /// VoiceOver hint describing the primary tap action.
    let accessibilityHint: String

    /// Spoken form of the visible icon-and-value subtitle (community, score,
    /// comments, age), since the visible subtitle renders SF Symbols inline that
    /// VoiceOver cannot pronounce.
    let subtitleAccessibilityLabel: String

    /// The thumbnail a cell shows for `row`, plus the full-resolution image URL
    /// (non-nil only for image posts, used to open the viewer). Single source
    /// for both `init` and prefetching so the feed and its pre-warm agree.
    ///
    /// Image posts show the image and open the viewer; external-link posts that
    /// carry an embed image show it inline (tap opens the post); everything else
    /// is the text placeholder.
    static func thumbnail(
        for row: PostListRow,
        postContentDetector: PostContentDetectorServiceType
    ) -> (thumbnail: Thumbnail, fullImageUrl: URL?) {
        let url = row.url.flatMap { URL(string: $0) }
        let thumbnailUrl = row.thumbnailUrl.flatMap { URL(string: $0) }
        switch postContentDetector.contentTypeForUrl(
            url: url,
            thumbnailUrl: thumbnailUrl,
            embedTitle: row.urlEmbedTitle,
            embedDescription: row.urlEmbedDescription
        ) {
        case let .image(image):
            return (.image(thumbnailUrl: image.thumbnailUrl ?? image.imageUrl), image.imageUrl)
        case .externalLink:
            if let thumbnailUrl {
                return (.linkImage(thumbnailUrl: thumbnailUrl), nil)
            }
            return (.text, nil)
        case .textOrEmpty:
            return (.text, nil)
        }
    }

    /// The thumbnail image URL a cell would load for this row, or nil when the
    /// post renders as the text placeholder. Lets the feed warm the image cache
    /// a few rows ahead of scroll without building the full view model.
    static func prefetchThumbnailUrl(
        for row: PostListRow,
        postContentDetector: PostContentDetectorServiceType
    ) -> URL? {
        switch thumbnail(for: row, postContentDetector: postContentDetector).thumbnail {
        case let .image(thumbnailUrl), let .linkImage(thumbnailUrl):
            return thumbnailUrl
        case .text:
            return nil
        }
    }

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

        (thumbnail, fullImageUrl) = Self.thumbnail(for: row, postContentDetector: postContentDetector)

        accessibilityLabel = Self.makeAccessibilityLabel(row: row, voteStatus: voteStatus)
        accessibilityHint = NSLocalizedString(
            "Opens the post and its comments",
            comment: "VoiceOver hint for a post in the list"
        )

        var subtitlePieces: [String] = [
            row.communityName,
            VoteAccessibility.scoreLabel(score: row.score, voteStatus: voteStatus),
            CommentsAccessibility.label(count: row.numberOfComments),
            row.published.relativeString,
        ]
        if row.isSaved {
            subtitlePieces.append(NSLocalizedString("Saved", comment: "VoiceOver: post is saved"))
        }
        subtitleAccessibilityLabel = subtitlePieces.joined(separator: ", ")
    }

    /// Assembles a natural-language description of the post for VoiceOver,
    /// ordered most-to-least important: read state, title, community, score,
    /// comment count, saved state.
    private static func makeAccessibilityLabel(row: PostListRow, voteStatus: VoteStatus) -> String {
        var parts: [String] = []

        if row.isRead {
            parts.append(NSLocalizedString("Read", comment: "VoiceOver: post has been read"))
        }

        parts.append(row.title)
        parts.append(String(
            format: NSLocalizedString("in %@", comment: "VoiceOver: community a post belongs to"),
            row.communityName
        ))
        parts.append(VoteAccessibility.scoreLabel(score: row.score, voteStatus: voteStatus))
        parts.append(CommentsAccessibility.label(count: row.numberOfComments))

        if row.isSaved {
            parts.append(NSLocalizedString("Saved", comment: "VoiceOver: post is saved"))
        }
        if row.isLocked {
            parts.append(NSLocalizedString("Locked", comment: "VoiceOver: post is locked"))
        }
        if row.isFeaturedCommunity || row.isFeaturedLocal {
            parts.append(NSLocalizedString("Pinned", comment: "VoiceOver: post is pinned"))
        }

        return parts.joined(separator: ", ")
    }
}
