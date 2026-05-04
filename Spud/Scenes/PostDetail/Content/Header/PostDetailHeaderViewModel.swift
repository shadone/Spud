//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Down
import Foundation
import LemmyKit
import OSLog
import SpudDataKit
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
        case post(URL, thumbnailUrl: URL?)
        case linkPreview(url: URL, thumbnailUrl: URL?)
    }

    let title: NSAttributedString
    let body: NSAttributedString
    let attribution: NSAttributedString
    let subtitleScore: NSAttributedString
    let subtitleComments: NSAttributedString
    let subtitleAge: NSAttributedString
    let isUpvoted: Bool
    let isDownvoted: Bool
    let image: HeaderImage

    init(
        row: PostDetailHeaderRow,
        appearance: AppearanceServiceType,
        postContentDetector: PostContentDetectorServiceType
    ) {
        let textSizeAdjustment = appearance.postDetail.textSizeAdjustment

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

        let stylerConfig = PostDetailAppearance.bodyStylerConfiguration(for: textSizeAdjustment)
        body = Down(markdownString: row.body ?? "")
            .toAttributedString(styler: DownStyler(configuration: stylerConfig))

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

        let inString = NSAttributedString(string: "in ", attributes: secondaryAttributes)
        let communityName = NSAttributedString(string: row.communityName, attributes: secondaryHighlightedAttributes)
        let byString = NSAttributedString(string: " by ", attributes: secondaryAttributes)
        let creator = NSAttributedString(string: row.creatorName, attributes: creatorAttributes)
        attribution = [inString, communityName, byString, creator].joined()

        let urlValue = row.url.flatMap { URL(string: $0) }
        let thumbnailUrlValue = row.thumbnailUrl.flatMap { URL(string: $0) }
        let contentType = postContentDetector.contentTypeForUrl(
            url: urlValue,
            thumbnailUrl: thumbnailUrlValue,
            embedTitle: row.urlEmbedTitle,
            embedDescription: row.urlEmbedDescription
        )

        switch contentType {
        case let .image(image):
            self.image = .post(image.imageUrl, thumbnailUrl: image.thumbnailUrl)
        case let .externalLink(link):
            image = .linkPreview(url: link.url, thumbnailUrl: thumbnailUrlValue)
        case .textOrEmpty:
            image = .none
        }
    }
}
