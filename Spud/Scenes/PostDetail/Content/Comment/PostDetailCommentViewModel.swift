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

/// A small pill in the comment header line marking the author's role or status
/// (OP / MOD / ADMIN / BOT / BANNED / SUSPENDED). Pure value; the cell renders it.
struct CommentBadge: Equatable {
    let text: String
    /// Optional leading SF Symbol (e.g. a bot/banned glyph).
    let symbolName: String?
    /// OP follows the app accent (resolved in the cell); everything else uses
    /// `color` directly.
    let usesAccent: Bool
    let color: UIColor
    /// Solid fill (a distinguished moderator/admin statement) vs a tinted pill.
    let solid: Bool
}

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

    /// Author role/status pills shown after the name, in order.
    let badges: [CommentBadge]

    /// One colored rail per ancestor depth, leading edge first. Drives the
    /// stacked Apollo-style depth rails. Empty for top-level comments.
    let depthRailColors: [UIColor]

    /// `true` when this comment's author is the post's author (drives the "OP"
    /// badge and the VoiceOver hint).
    let isOriginalPoster: Bool

    /// An official moderator/admin statement: the cell gives it an accent bar
    /// and a tinted background, and any MOD/ADMIN badge renders solid.
    let isDistinguished: Bool

    /// `true` for moderator-removed comments — the cell dims the row.
    let isDeemphasized: Bool

    /// `true` when the author is blocked and not revealed: the cell collapses
    /// the row to a "Blocked user · Show" affordance.
    let isBlockedFolded: Bool

    /// Folded blocked-row label ("Blocked user") and its reveal action label.
    let blockedFoldedText: NSAttributedString?
    let blockedShowText: NSAttributedString?

    /// `true` when this comment is collapsed and its subtree is hidden.
    let isCollapsed: Bool

    /// The number of descendants hidden underneath this collapsed comment, or
    /// `nil` when the comment is expanded (no badge shown).
    let collapsedBadgeText: NSAttributedString?

    /// Spoken form of the metadata line (score, age, depth, saved/moderation
    /// and collapsed state), since the visible subtitle renders SF Symbols
    /// inline. The author (a link) and body are read as their own elements.
    /// nil for "load more" placeholders.
    let subtitleAccessibilityLabel: String?

    /// VoiceOver hint describing the collapse/expand tap action.
    let collapseAccessibilityHint: String

    init(
        row: PostDetailCommentRow,
        appearance: AppearanceServiceType,
        postCreatorPersonId: Int64? = nil,
        isCollapsed: Bool = false,
        collapsedDescendantCount: Int? = nil,
        isBlockedRevealed: Bool = false
    ) {
        let textSizeAdjustment = appearance.postDetail.textSizeAdjustment

        let isDeleted = row.isDeleted == true
        let isRemoved = row.isRemoved == true
        let distinguished = row.isDistinguished == true
        let accountDeleted = row.isCreatorAccountDeleted == true
        let banned = row.isCreatorBannedFromCommunity == true || row.isCreatorSiteBanned == true
        let blocked = row.isCreatorBlocked == true

        isDistinguished = distinguished
        isDeemphasized = isRemoved

        // The author is the post's author when their person ids match — drives
        // the "OP" badge. nil ids never match (no false positive).
        isOriginalPoster = row.creatorPersonId != nil && row.creatorPersonId == postCreatorPersonId

        let bodyFont = UIFont.scaledSystemFont(
            style: .body,
            relativeSize: textSizeAdjustment,
            weight: .regular
        )
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
        // Monospaced digits for score / age so numbers stay aligned and don't
        // jitter, matching the feed cell.
        let monoAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.scaledMonospaceDigitSystemFont(
                style: .body,
                relativeSize: -1 + textSizeAdjustment,
                weight: .regular
            ),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        let linkTextAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.scaledSystemFont(
                style: .body,
                relativeSize: -1 + textSizeAdjustment,
                weight: .regular
            ),
            .foregroundColor: UIColor.link,
        ]

        // MARK: Author name

        var authorAttributes = authorAttributesBase
        if accountDeleted {
            authorAttributes[.font] = Self.italic(authorAttributes[.font] as? UIFont)
            authorAttributes[.foregroundColor] = UIColor.tertiaryLabel
        }
        if banned {
            authorAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            authorAttributes[.strikethroughColor] = UIColor.systemRed
        }
        // The author links to their profile — except an account-deleted author,
        // which has no profile to open.
        if
            !accountDeleted,
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
        let displayName = accountDeleted ? "[deleted]" : (row.creatorName ?? "")
        author = NSAttributedString(string: displayName, attributes: authorAttributes)

        // MARK: Badges

        var badges: [CommentBadge] = []
        if isOriginalPoster {
            badges.append(CommentBadge(text: "OP", symbolName: nil, usesAccent: true, color: .systemTeal, solid: false))
        }
        if row.isCreatorModerator == true {
            badges.append(CommentBadge(text: "MOD", symbolName: nil, usesAccent: false, color: .systemGreen, solid: distinguished))
        }
        if row.isCreatorAdmin == true {
            badges.append(CommentBadge(text: "ADMIN", symbolName: nil, usesAccent: false, color: .systemIndigo, solid: distinguished))
        }
        if row.isCreatorBot == true {
            badges.append(CommentBadge(text: "BOT", symbolName: "cpu", usesAccent: false, color: .systemGray, solid: false))
        }
        if row.isCreatorBannedFromCommunity == true {
            badges.append(CommentBadge(text: "BANNED", symbolName: "person.fill.xmark", usesAccent: false, color: .systemRed, solid: false))
        }
        if row.isCreatorSiteBanned == true {
            badges.append(CommentBadge(text: "SUSPENDED", symbolName: "person.fill.xmark", usesAccent: false, color: .systemRed, solid: false))
        }
        self.badges = badges

        // MARK: Body / moderation placeholder

        if isDeleted {
            body = Self.placeholder(
                symbolName: "trash",
                text: NSLocalizedString("Comment deleted by author", comment: "Placeholder for a comment the author deleted"),
                tint: .secondaryLabel,
                bodyFont: bodyFont
            )
        } else if isRemoved {
            let removedBase = NSLocalizedString("Removed by moderator", comment: "Placeholder for a comment a moderator removed")
            let removedText: String = {
                guard let reason = row.removedReason, !reason.isEmpty else { return removedBase }
                return "\(removedBase) · \(reason)"
            }()
            body = Self.placeholder(
                symbolName: "trash.slash",
                text: removedText,
                tint: .systemOrange,
                bodyFont: bodyFont
            )
        } else {
            // Rendered (and cached) through `MarkdownRenderer` so a long thread
            // does not re-parse markdown on every cell dequeue. The comment list
            // pre-warms this cache off the main thread, so steady state is a
            // cache hit here.
            let bodyMarkdown = row.body ?? ""
            body = MarkdownRenderer.shared.attributedString(
                markdown: bodyMarkdown,
                key: MarkdownRenderer.imageBodyKey(markdown: bodyMarkdown, textSizeAdjustment: textSizeAdjustment),
                makeStyler: {
                    BodyImageStyler(configuration: PostDetailAppearance.bodyStylerConfiguration(for: textSizeAdjustment))
                }
            )
        }

        // MARK: Blocked-user fold

        isBlockedFolded = blocked && !isBlockedRevealed
        if blocked, !isBlockedRevealed {
            blockedFoldedText = NSAttributedString(
                string: NSLocalizedString("Blocked user", comment: "Folded row for a comment from a blocked user"),
                attributes: secondaryAttributes
            )
            blockedShowText = NSAttributedString(
                string: NSLocalizedString("Show", comment: "Reveal a blocked user's comment"),
                attributes: linkTextAttributes
            )
        } else {
            blockedFoldedText = nil
            blockedShowText = nil
        }

        // MARK: Subtitle (score · age · saved)

        let voteStatus: VoteStatus = {
            switch row.voteStatus {
            case 1: return .up
            case 0: return .down
            default: return .neutral
            }
        }()

        let space = NSAttributedString(string: "  ", attributes: secondaryAttributes)
        // A deleted/removed comment has no meaningful score — hiding it is what
        // makes the placeholder read as "gone" rather than a normal downvoted row.
        let hideScore = isDeleted || isRemoved
        var subtitlePieces: [NSAttributedString] = []
        if !hideScore {
            subtitlePieces.append(IconValueFormatter.attributedString(
                numberOfVotesOrScore: row.score,
                voteStatus: voteStatus,
                attributes: monoAttributes,
                appearance: appearance.general
            ))
            subtitlePieces.append(space)
        }
        if let published = row.published {
            subtitlePieces.append(IconValueFormatter.attributedString(
                relativeDate: published,
                attributes: monoAttributes
            ))
        }
        if row.isSaved == true {
            var savedAttributes = secondaryAttributes
            savedAttributes[.foregroundColor] = UIColor.systemYellow
            subtitlePieces.append(space)
            subtitlePieces.append(NSAttributedString.symbol(
                from: UIImage(systemName: "bookmark.fill")!,
                attributes: savedAttributes
            ))
        }
        subtitle = subtitlePieces.joined()

        if let moreChildCount = row.moreChildCount {
            isMore = true
            let text: String = moreChildCount == 1
                ? "1 more reply"
                : "\(moreChildCount) more replies"
            moreText = NSAttributedString(string: text, attributes: linkTextAttributes)
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

        // MARK: Accessibility

        if isMore {
            subtitleAccessibilityLabel = nil
            collapseAccessibilityHint = NSLocalizedString(
                "Loads more replies",
                comment: "VoiceOver hint for the load-more-replies row"
            )
        } else {
            // The subtitle element carries the full comment metadata for
            // VoiceOver — score, age, depth, collapsed and moderation state —
            // since the visible run is icon glyphs it cannot pronounce. The
            // author (a link) and body are read as their own elements.
            var pieces: [String] = []
            if !hideScore {
                pieces.append(VoteAccessibility.scoreLabel(score: row.score, voteStatus: voteStatus))
            }
            if isOriginalPoster {
                pieces.append(NSLocalizedString("original poster", comment: "VoiceOver: comment written by the post's author"))
            }
            if row.isCreatorModerator == true {
                pieces.append(NSLocalizedString("moderator", comment: "VoiceOver: comment by a community moderator"))
            }
            if row.isCreatorAdmin == true {
                pieces.append(NSLocalizedString("admin", comment: "VoiceOver: comment by an instance admin"))
            }
            if row.isCreatorBot == true {
                pieces.append(NSLocalizedString("bot account", comment: "VoiceOver: comment by a bot account"))
            }
            if row.isCreatorBannedFromCommunity == true {
                pieces.append(NSLocalizedString("banned from this community", comment: "VoiceOver: author banned from the community"))
            }
            if row.isCreatorSiteBanned == true {
                pieces.append(NSLocalizedString("suspended site-wide", comment: "VoiceOver: author suspended instance-wide"))
            }
            if let published = row.published {
                pieces.append(published.relativeString)
            }
            if depth > 1 {
                pieces.append(String(
                    format: NSLocalizedString("depth %lld", comment: "VoiceOver: comment nesting depth"),
                    depth
                ))
            }
            if isCollapsed {
                if let count = collapsedDescendantCount, count > 0 {
                    pieces.append(String(
                        format: NSLocalizedString(
                            "collapsed, %lld hidden",
                            comment: "VoiceOver: collapsed comment with hidden descendant count"
                        ),
                        count
                    ))
                } else {
                    pieces.append(NSLocalizedString("collapsed", comment: "VoiceOver: collapsed comment"))
                }
            }
            if row.isSaved == true {
                pieces.append(NSLocalizedString("Saved", comment: "VoiceOver: comment is saved"))
            }
            if isRemoved {
                pieces.append(NSLocalizedString("Removed by moderator", comment: "VoiceOver: comment removed by moderator"))
            }
            if isDeleted {
                pieces.append(NSLocalizedString("Deleted by author", comment: "VoiceOver: comment deleted by author"))
            }
            if distinguished {
                pieces.append(NSLocalizedString("Distinguished", comment: "VoiceOver: distinguished moderator comment"))
            }
            subtitleAccessibilityLabel = pieces.joined(separator: ", ")

            collapseAccessibilityHint = isCollapsed
                ? NSLocalizedString("Expands the comment thread", comment: "VoiceOver hint for a collapsed comment")
                : NSLocalizedString("Collapses the comment thread", comment: "VoiceOver hint for an expanded comment")
        }
    }

    /// An italic variant of `font`, or `font` unchanged if the italic trait
    /// can't be applied.
    private static func italic(_ font: UIFont?) -> UIFont {
        let font = font ?? .preferredFont(forTextStyle: .body)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) else {
            return font
        }
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// A moderation placeholder body: a leading icon and an italic label that
    /// replaces the (empty) content of a deleted or removed comment.
    private static func placeholder(
        symbolName: String,
        text: String,
        tint: UIColor,
        bodyFont: UIFont
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if let image = UIImage(systemName: symbolName) {
            result.append(NSAttributedString.symbol(
                from: image,
                attributes: [.font: bodyFont, .foregroundColor: tint]
            ))
            result.append(NSAttributedString(string: "  "))
        }
        result.append(NSAttributedString(
            string: text,
            attributes: [.font: italic(bodyFont), .foregroundColor: UIColor.secondaryLabel]
        ))
        return result
    }
}
