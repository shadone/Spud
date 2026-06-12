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

    /// One colored rail per ancestor depth, leading edge first. Drives the
    /// stacked Apollo-style depth rails. Empty for top-level comments.
    let depthRailColors: [UIColor]

    /// `true` when this comment is collapsed and its subtree is hidden.
    let isCollapsed: Bool

    /// The number of descendants hidden underneath this collapsed comment, or
    /// `nil` when the comment is expanded (no badge shown).
    let collapsedBadgeText: NSAttributedString?

    init(
        row: PostDetailCommentRow,
        appearance: AppearanceServiceType,
        isCollapsed: Bool = false,
        collapsedDescendantCount: Int? = nil
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
        var subtitlePieces: [NSAttributedString] = [upvotes, space, age]
        if row.isSaved == true {
            var savedAttributes = secondaryAttributes
            savedAttributes[.foregroundColor] = UIColor.systemYellow
            subtitlePieces.append(space)
            subtitlePieces.append(NSAttributedString.symbol(
                from: UIImage(systemName: "bookmark.fill")!,
                attributes: savedAttributes
            ))
        }

        // Moderation / content-status badges: removed (red), distinguished
        // (green shield), or deleted-by-author (red).
        for badge in CommentStatusBadge.badges(
            isRemoved: row.isRemoved == true,
            isDistinguished: row.isDistinguished == true,
            isDeleted: row.isDeleted == true
        ) {
            var attrs = secondaryAttributes
            attrs[.foregroundColor] = badge.color
            subtitlePieces.append(space)
            subtitlePieces.append(NSAttributedString.symbol(
                from: UIImage(systemName: badge.symbolName)!,
                attributes: attrs
            ))
        }

        subtitle = subtitlePieces.joined()

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
        let theme = appearance.postDetail.commentRibbonTheme
        let colors = theme.colors

        // One rail per ancestor level (depth 1 = top-level => no ancestor rail).
        // Depth d has (d - 1) ancestor rails; each rail's hue cycles through the
        // theme palette by its own depth so the same depth always reads as the
        // same color, which is what makes the thread scannable.
        let railCount = max(0, Int(depth) - 1)
        if colors.isEmpty {
            depthRailColors = Array(repeating: .lightGray, count: railCount)
        } else {
            depthRailColors = (0..<railCount).map { level in
                colors[level % colors.count]
            }
        }

        self.isCollapsed = isCollapsed
        if let count = collapsedDescendantCount, count > 0 {
            var badgeAttributes = secondaryAttributes
            badgeAttributes[.foregroundColor] = UIColor.secondaryLabel
            badgeAttributes[.font] = UIFont.scaledSystemFont(
                style: .caption1,
                relativeSize: textSizeAdjustment,
                weight: .semibold
            )
            collapsedBadgeText = NSAttributedString(
                string: "+\(count)",
                attributes: badgeAttributes
            )
        } else {
            collapsedBadgeText = nil
        }
    }
}
