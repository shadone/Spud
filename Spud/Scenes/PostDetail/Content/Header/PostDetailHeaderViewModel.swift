//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog
import SpudDataKit
import SpudMarkdownKit
import SpudUtilKit
import UIKit

private let logger = Logger.app

/// Plain-value snapshot consumed by `PostDetailHeaderCell`. Built once per
/// `PostDetailHeaderRow` emission. The cell drops Combine and applies these
/// values directly; image loading is async via Task in the cell itself.
@MainActor
struct PostDetailHeaderViewModel {
    enum HeaderImage: Equatable {
        case none
        /// `imageSize` is the image's pixel dimensions when known (from
        /// `image_details`), so the cell can reserve the exact height before the
        /// image loads. nil when the instance didn't report them.
        case post(URL, thumbnailUrl: URL?, imageSize: CGSize?)
        case video(videoUrl: URL, thumbnailUrl: URL?)
        case linkPreview(url: URL, thumbnailUrl: URL?, title: String?)
    }

    let title: NSAttributedString
    let bodyBlocks: [MarkdownBlock]
    /// The text-size preference used to size `bodyBlocks`. Exposed so the cell can
    /// rebuild `MarkdownBodyView` with a matching context when the preference
    /// changes between configure calls.
    let textSizeAdjustment: CGFloat
    let attribution: NSAttributedString
    let subtitleScore: NSAttributedString
    let subtitleComments: NSAttributedString
    let subtitleAge: NSAttributedString
    let isUpvoted: Bool
    let isDownvoted: Bool
    let isSaved: Bool
    let image: HeaderImage

    /// True when the post or its community is marked NSFW.
    let isNsfw: Bool
    /// Mirrors `PreferencesService.blurNsfw` at configure time.
    let blurNsfw: Bool
    /// True once the user has tapped to reveal during this open-post session.
    let isRevealed: Bool
    /// Computed convenience: the image should be blurred when NSFW, the preference
    /// is on, and the user has not yet revealed it this session.
    var isImageBlurred: Bool {
        isNsfw && blurNsfw && !isRevealed
    }

    /// Spoken forms of the icon-and-value subtitle pieces, since the visible
    /// labels render SF Symbols that VoiceOver cannot pronounce.
    let subtitleScoreAccessibilityLabel: String
    let subtitleCommentsAccessibilityLabel: String
    let subtitleAgeAccessibilityLabel: String

    init(
        row: PostDetailHeaderRow,
        appearance: AppearanceServiceType,
        postContentDetector: PostContentDetectorServiceType,
        blurNsfw: Bool = false,
        isRevealed: Bool = false
    ) {
        isNsfw = row.isNsfw
        self.blurNsfw = blurNsfw
        self.isRevealed = isRevealed

        let textSizeAdjustment = appearance.postDetail.textSizeAdjustment
        self.textSizeAdjustment = textSizeAdjustment

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.label,
            .font: UIFont.scaledSystemFont(
                style: .title2,
                relativeSize: 5 + textSizeAdjustment,
                weight: .medium
            ),
        ]
        title = NSAttributedString(string: row.title, attributes: titleAttributes)

        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.scaledSystemFont(
                style: .body,
                relativeSize: -1 + textSizeAdjustment,
                weight: .regular
            ),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        let secondaryHighlightedAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.scaledSystemFont(
                style: .body,
                relativeSize: -1 + textSizeAdjustment,
                weight: .medium
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
        isUpvoted = voteStatus.isUp
        isDownvoted = voteStatus.isDown
        isSaved = row.isSaved

        subtitleScore = IconValueFormatter.attributedString(
            numberOfVotesOrScore: row.score,
            voteStatus: voteStatus,
            attributes: secondaryAttributes,
            appearance: appearance.general
        )
        subtitleComments = IconValueFormatter.attributedString(
            numberOfComments: row.numberOfComments,
            attributes: secondaryAttributes
        )
        subtitleAge = IconValueFormatter.attributedString(
            relativeDate: row.published,
            attributes: secondaryAttributes
        )

        // The block-based renderer caches parsed markdown off the main thread,
        // so the header re-rendering on every vote/save is a cache hit here.
        let bodyMarkdown = row.body ?? ""
        bodyBlocks = MarkdownBlockCache.shared.blocks(for: bodyMarkdown)

        var creatorAttributes = secondaryHighlightedAttributes
        if
            let creatorInstanceUrl = URL(string: row.creatorInstanceActorId),
            let creatorInstance = InstanceActorId(from: creatorInstanceUrl)
        {
            creatorAttributes[.link] = URL.SpudInternalLink.person(
                personId: Int32(truncatingIfNeeded: row.creatorPersonId),
                instance: creatorInstance
            ).url
        }

        var communityAttributes = secondaryHighlightedAttributes
        if
            let communityActorId = row.communityActorId,
            let communityUrl = URL(string: communityActorId),
            let communityInstance = InstanceActorId(from: communityUrl)
        {
            communityAttributes[.link] = URL.SpudInternalLink.community(
                name: row.communityName,
                instance: communityInstance
            ).url
        }

        subtitleScoreAccessibilityLabel = VoteAccessibility.scoreLabel(
            score: row.score,
            voteStatus: voteStatus
        )
        subtitleCommentsAccessibilityLabel = CommentsAccessibility.label(count: row.numberOfComments)
        subtitleAgeAccessibilityLabel = row.published.relativeString

        // The `@instance` host stays quiet (tertiary) so it reads as metadata, never
        // competing with the community / creator display name — matching the muted
        // host style in the post-list rows. It carries the SAME `.link` as the name
        // so the whole handle ("News@instance") is one tap target; because name and
        // host share the link value and are adjacent, they coalesce into a single
        // link range.
        var instanceAttributes = secondaryAttributes
        instanceAttributes[.foregroundColor] = UIColor.tertiaryLabel
        var communityInstanceAttributes = instanceAttributes
        communityInstanceAttributes[.link] = communityAttributes[.link]
        var creatorInstanceAttributes = instanceAttributes
        creatorInstanceAttributes[.link] = creatorAttributes[.link]

        // Prefer the community's display name (title); fall back to its handle.
        let communityDisplayName: String = {
            let title = row.communityTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let title, !title.isEmpty { return title }
            return row.communityName
        }()
        let communityHost = row.communityActorId.flatMap { InstanceActorId(from: $0)?.host }
        let creatorHost = InstanceActorId(from: row.creatorInstanceActorId)?.host

        // "in <Community>@host by <Creator>@host" — the whole handle (name + host) is
        // the tap target.
        var pieces: [NSAttributedString] = [
            NSAttributedString(string: "in ", attributes: secondaryAttributes),
            NSAttributedString(string: communityDisplayName, attributes: communityAttributes),
        ]
        if let communityHost {
            pieces.append(NSAttributedString(string: "@\(communityHost)", attributes: communityInstanceAttributes))
        }
        pieces.append(NSAttributedString(string: " by ", attributes: secondaryAttributes))
        pieces.append(NSAttributedString(string: row.creatorName, attributes: creatorAttributes))
        if let creatorHost {
            pieces.append(NSAttributedString(string: "@\(creatorHost)", attributes: creatorInstanceAttributes))
        }
        attribution = pieces.joined()

        let urlValue = row.url.flatMap { URL(string: $0) }
        let thumbnailUrlValue = row.thumbnailUrl.flatMap { URL(string: $0) }
        let contentType = postContentDetector.contentTypeForUrl(
            url: urlValue,
            thumbnailUrl: thumbnailUrlValue,
            embedTitle: row.urlEmbedTitle,
            embedDescription: row.urlEmbedDescription
        )

        let imageSize: CGSize? = row.imageWidth.flatMap { width in
            row.imageHeight.map { height in
                CGSize(width: width, height: height)
            }
        }

        switch contentType {
        case let .image(image):
            self.image = .post(image.imageUrl, thumbnailUrl: image.thumbnailUrl, imageSize: imageSize)
        case let .video(video):
            image = .video(videoUrl: video.videoUrl, thumbnailUrl: video.thumbnailUrl)
        case let .externalLink(link):
            image = .linkPreview(url: link.url, thumbnailUrl: thumbnailUrlValue, title: row.urlEmbedTitle)
        case .textOrEmpty:
            image = .none
        }
    }
}
