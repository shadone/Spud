//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

@MainActor
struct PostListPostViewModel {
    enum Thumbnail: Equatable {
        /// Post points to an image (or has a thumbnail) — load it via ImageService.
        /// Tapping it opens the full-screen viewer.
        case image(thumbnailUrl: URL)
        /// External-link post that carries an embed image — show it inline with a
        /// link badge. Tapping opens the external link.
        case linkImage(thumbnailUrl: URL, linkUrl: URL)
        /// External-link post with no embed image — show the web placeholder so
        /// it reads as a link, not a self-post. Tapping opens the external link.
        case link(linkUrl: URL)
        /// Playable video post. Show the poster (if any) with a play indicator;
        /// tapping plays the video.
        case video(posterUrl: URL?, videoUrl: URL)
        /// Text-only post; render the placeholder icon.
        case text
    }

    let title: NSAttributedString
    let subtitle: NSAttributedString
    let thumbnail: Thumbnail
    let isSaved: Bool

    /// The user's current vote on the post, driving the inline vote-arrow colors.
    let voteStatus: VoteStatus

    /// Tint for the upvote arrow when the post is upvoted.
    let upvoteActiveColor: UIColor

    /// Tint for the downvote arrow when the post is downvoted.
    let downvoteActiveColor: UIColor

    /// For external-link posts, the canonical domain (e.g. "mozilla.org") shown
    /// as a quiet line under the title; `nil` for image / video / text posts.
    let domainText: NSAttributedString?

    /// A short, single-line preview of the post's self-text body, or `nil` when
    /// the post has no body (link / image-only posts).
    let bodyPreview: NSAttributedString?

    /// Full-resolution image url when the post is an image post, used to open
    /// the full-screen viewer from the list thumbnail. nil for non-image posts.
    let fullImageUrl: URL?

    /// Where the cell should place the thumbnail (or whether to hide it).
    let thumbnailPosition: ThumbnailPosition

    /// Whether the cell shows the trailing up/down vote arrows.
    let showVoteButtons: Bool

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
        let content = content(for: row, postContentDetector: postContentDetector)
        return (content.thumbnail, content.fullImageUrl)
    }

    /// Resolves a row to everything the cell derives from its content type in one
    /// pass: the thumbnail, the full-resolution image url (image posts only), and
    /// the canonical link domain (external-link posts only).
    static func content(
        for row: PostListRow,
        postContentDetector: PostContentDetectorServiceType
    ) -> (thumbnail: Thumbnail, fullImageUrl: URL?, domain: String?) {
        let url = row.url.flatMap { URL(string: $0) }
        let thumbnailUrl = row.thumbnailUrl.flatMap { URL(string: $0) }
        switch postContentDetector.contentTypeForUrl(
            url: url,
            thumbnailUrl: thumbnailUrl,
            embedTitle: row.urlEmbedTitle,
            embedDescription: row.urlEmbedDescription
        ) {
        case let .image(image):
            return (.image(thumbnailUrl: image.thumbnailUrl ?? image.imageUrl), image.imageUrl, nil)
        case let .video(video):
            return (.video(posterUrl: video.thumbnailUrl, videoUrl: video.videoUrl), nil, nil)
        case let .externalLink(link):
            let domain = link.url.canonicalHost
            if let thumbnailUrl {
                return (.linkImage(thumbnailUrl: thumbnailUrl, linkUrl: link.url), nil, domain)
            }
            return (.link(linkUrl: link.url), nil, domain)
        case .textOrEmpty:
            return (.text, nil, nil)
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
        case let .image(thumbnailUrl), let .linkImage(thumbnailUrl, _):
            return thumbnailUrl
        case let .video(posterUrl, _):
            return posterUrl
        case .link, .text:
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
        showVoteButtons = appearance.postList.showVoteButtons

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
        // The `@instance` handle stays quiet (tertiary) so it reads as metadata,
        // never competing with the community name or the title.
        let instanceAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.scaledSystemFont(
                style: .body,
                relativeSize: -1 + textSizeAdjustment,
                weight: .regular
            ),
            .foregroundColor: UIColor.tertiaryLabel,
        ]
        // Score / comments / age use monospaced digits so the numbers don't
        // jitter as they tick and columns of rows stay visually aligned.
        let monoAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.scaledMonospaceDigitSystemFont(
                style: .body,
                relativeSize: -1 + textSizeAdjustment,
                weight: .regular
            ),
            .foregroundColor: UIColor.secondaryLabel,
        ]

        // Spud stores votes as 1 = up, 0 = down, NULL = neutral (Lemmy's -1 is
        // mapped to 0 at import time); see AppDatabase migrations.
        let voteStatus: VoteStatus = {
            switch row.voteStatus {
            case 1: return .up
            case 0: return .down
            default: return .neutral
            }
        }()
        self.voteStatus = voteStatus
        upvoteActiveColor = appearance.general.upvoteButtonActiveColor
        downvoteActiveColor = appearance.general.downvoteButtonActiveColor

        // The lone breaking opportunity in the subtitle: when the line is too
        // narrow for the whole thing, it wraps here — dropping the fixed-width
        // metadata to a second line and leaving the variable-width community
        // handle on the first. See `PostListPostCell.subtitleLabel`.
        let handleSpace = NSAttributedString(string: "  ", attributes: secondaryAttributes)
        // Non-breaking double-space keeps the metadata run (score, comments,
        // age, and any saved/badge markers) together as one unbreakable unit so
        // it never splits across lines — the subtitle only ever wraps at
        // `handleSpace`, after the community name.
        let space = NSAttributedString(string: "\u{00a0}\u{00a0}", attributes: secondaryAttributes)

        // "community@instance" — the name in the label color, the host quiet.
        var handlePieces = [NSAttributedString(string: row.communityName, attributes: communityAttributes)]
        if let instanceHost = row.communityActorId.flatMap({ InstanceActorId(from: $0)?.host }) {
            handlePieces.append(NSAttributedString(string: "@\(instanceHost)", attributes: instanceAttributes))
        }

        var pieces: [NSAttributedString] = [
            handlePieces.joined(),
            handleSpace,
            IconValueFormatter.attributedString(
                numberOfVotesOrScore: row.score,
                voteStatus: voteStatus,
                attributes: monoAttributes,
                appearance: appearance.general
            ),
            space,
            IconValueFormatter.attributedString(
                numberOfComments: row.numberOfComments,
                attributes: monoAttributes
            ),
            space,
            IconValueFormatter.attributedString(
                relativeDate: row.published,
                attributes: monoAttributes
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

        let content = Self.content(for: row, postContentDetector: postContentDetector)
        thumbnail = content.thumbnail
        fullImageUrl = content.fullImageUrl
        domainText = content.domain.map { NSAttributedString(string: $0, attributes: monoAttributes) }

        bodyPreview = Self.bodyPreview(
            from: row.body,
            attributes: [
                .font: UIFont.scaledSystemFont(
                    style: .body,
                    relativeSize: -2 + textSizeAdjustment,
                    weight: .regular
                ),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        )

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

    /// Collapses a self-text body into a single trimmed line for the feed
    /// preview, or `nil` when there's nothing to show. Markdown syntax is
    /// stripped via the pure `MarkdownPlainText` helper — cheap string work that
    /// never touches the main-thread markdown parser/renderer; the cell clamps
    /// the result to two lines.
    private static func bodyPreview(
        from body: String?,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString? {
        guard let body else { return nil }
        let plain = MarkdownPlainText.preview(from: body)
        guard !plain.isEmpty else { return nil }
        return NSAttributedString(string: plain, attributes: attributes)
    }
}
