//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Down
import Foundation
import OSLog
import SpudDataKit
import SpudUtilKit
import UIKit

private let logger = Logger.app

/// Plain-value snapshot consumed by `PostDetailCommentCell`. Built once per
/// `PostDetailCommentRow` emission. The cell drops Combine and applies these
/// values directly.
@MainActor
struct PostDetailCommentViewModel {
    let author: NSAttributedString
    let body: NSAttributedString
    let subtitle: NSAttributedString
    let isMore: Bool
    let moreText: NSAttributedString?
    let indentationRibbonWidth: CGFloat
    let indentationRibbonLeadingMargin: CGFloat
    let indentationRibbonColor: UIColor

    private static let indentationRibbonStandardWidth: CGFloat = 2

    init(
        row: PostDetailCommentRow,
        appearance: AppearanceServiceType
    ) {
        let textSizeAdjustment = appearance.postDetail.textSizeAdjustment

        let authorAttributesBase: [NSAttributedString.Key: Any] = [
            .font: UIFont.scaledSystemFont(
                style: .body,
                relativeSize: textSizeAdjustment,
                weight: .medium
            ),
        ]
        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.scaledSystemFont(
                style: .body,
                relativeSize: -1 + textSizeAdjustment,
                weight: .regular
            ),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        let moreTextAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.scaledSystemFont(
                style: .body,
                relativeSize: -1 + textSizeAdjustment,
                weight: .regular
            ),
            .foregroundColor: UIColor.link,
        ]

        var authorAttributes = authorAttributesBase
        if
            let personId = row.creatorPersonId,
            let actorIdString = row.creatorInstanceActorId,
            let url = URL(string: actorIdString),
            let instance = InstanceActorId(from: url)
        {
            authorAttributes[.link] = URL.SpudInternalLink.person(
                personId: Int32(truncatingIfNeeded: personId),
                instance: instance
            ).url
        }
        author = NSAttributedString(string: row.creatorName ?? "", attributes: authorAttributes)

        let stylerConfig = PostDetailAppearance.bodyStylerConfiguration(for: textSizeAdjustment)
        body = Down(markdownString: row.body ?? "")
            .toAttributedString(styler: DownStyler(configuration: stylerConfig))

        let voteStatus: VoteStatus = {
            switch row.voteStatus {
            case 1: return .up
            case 0: return .down
            default: return .neutral
            }
        }()

        let space = NSAttributedString(string: "  ", attributes: secondaryAttributes)
        let upvotes = IconValueFormatter.attributedString(
            numberOfVotesOrScore: row.score,
            voteStatus: voteStatus,
            attributes: secondaryAttributes,
            appearance: appearance.general
        )
        let age: NSAttributedString = {
            guard let published = row.published else { return NSAttributedString() }
            return IconValueFormatter.attributedString(
                relativeDate: published,
                attributes: secondaryAttributes
            )
        }()
        subtitle = [upvotes, space, age].joined()

        if let moreChildCount = row.moreChildCount {
            isMore = true
            let text: String = moreChildCount == 1
                ? "1 more reply"
                : "\(moreChildCount) more replies"
            moreText = NSAttributedString(string: text, attributes: moreTextAttributes)
        } else {
            isMore = false
            moreText = nil
        }

        let depth = row.depth
        indentationRibbonWidth = depth == 1 ? 0 : Self.indentationRibbonStandardWidth

        let leadingMargin: CGFloat = 4
        indentationRibbonLeadingMargin =
            (Self.indentationRibbonStandardWidth + 4) * CGFloat(max(0, depth - 1)) + leadingMargin

        let theme = appearance.postDetail.commentRibbonTheme
        let colors = theme.colors
        let index = max(0, Int(depth - 1) % max(1, colors.count))
        indentationRibbonColor = colors.isEmpty ? .lightGray : colors[index]
    }
}
