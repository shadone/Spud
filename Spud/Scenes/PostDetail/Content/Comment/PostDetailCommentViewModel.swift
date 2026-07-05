//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog
import SpudDataKit
import SpudMarkdownKit
import SpudUIKit
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
    /// Parsed markdown block tree for the comment body.  Empty for deleted /
    /// removed comments (those use `body` for the styled placeholder instead).
    let bodyBlocks: [MarkdownBlock]
    /// The text-size preference baked into `body`; exposed so the cell can
    /// rebuild `MarkdownBodyView` with a matching context when the preference
    /// changes between configure calls.
    let textSizeAdjustment: CGFloat
    let commentDensity: PostDensity

    /// Previewable links found in the comment body, rendered as `LinkPreviewView`
    /// cards below the text. Empty for moderation placeholders (no blocks) and for
    /// comments without previewable links.
    let linkPreviews: [CommentLinkPreview]

    /// When `true`, the cell fetches video embed metadata (title + thumbnail) for
    /// recognised video link cards. Reflects `PreferencesService.fetchLinkEmbeds`
    /// at the time the view model is built.
    let fetchLinkEmbeds: Bool

    let subtitle: NSAttributedString
    let isMore: Bool
    let moreText: NSAttributedString?

    /// The current vote state on this comment — drives the score-pill fill and
    /// the pill's accessibility label.
    let voteStatus: VoteStatus

    /// The comment's display score. Moved out of the subtitle and into the
    /// score-pill in the voted state; still surfaced in the accessibility label.
    let score: Int64

    /// The upvote active fill color, resolved from the appearance at VM build
    /// time.  The cell reads this instead of reaching into the appearance service.
    let upvoteActiveColor: UIColor

    /// The downvote active fill color, resolved from the appearance at VM build
    /// time.
    let downvoteActiveColor: UIColor

    /// The pre-built attributed text for the score pill (arrow glyph + number),
    /// using the scaled monospaced font so the pill tracks Dynamic Type. `nil`
    /// for "load more" rows and deleted/removed comments (no meaningful score).
    ///
    /// Neutral state produces a `.secondaryLabel`-coloured no-fill string;
    /// voted states produce a white string intended to sit on `scorePillFillColor`.
    let scorePillText: NSAttributedString?

    /// The background fill for the score pill. `nil` for neutral (transparent
    /// background so the capsule is invisible, letting the score float inline).
    let scorePillFillColor: UIColor?

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

    /// `true` when this comment is new since the user's last visit. Drives the
    /// gutter dot and the fresh-wash treatment.
    let isNew: Bool

    /// The number of descendants hidden underneath this collapsed comment, or
    /// `nil` when the comment is expanded (no badge shown).
    let collapsedBadgeText: NSAttributedString?

    /// Count of *new* descendants hidden under this collapsed comment, for the
    /// accent "N new" pill. nil when none (the cell renders no pill). The cell
    /// builds the pill so the accent resolves from its `tintColor`.
    let collapsedNewDescendantCount: Int?

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
        collapsedNewDescendantCount: Int? = nil,
        isBlockedRevealed: Bool = false,
        isNew: Bool = false,
        fetchLinkEmbeds: Bool = false
    ) {
        let textSizeAdjustment = appearance.postDetail.textSizeAdjustment
        self.textSizeAdjustment = textSizeAdjustment
        commentDensity = appearance.postDetail.commentDensity

        let isDeleted = row.isDeleted == true
        let isRemoved = row.isRemoved == true
        let distinguished = row.isDistinguished == true
        let accountDeleted = row.isCreatorAccountDeleted == true
        let banned = row.isCreatorBannedFromCommunity == true || row.isCreatorSiteBanned == true
        let blocked = row.isCreatorBlocked == true

        isDistinguished = distinguished
        isDeemphasized = isRemoved
        self.isNew = isNew

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
        // which has no profile to open. The instance comes from the author's own
        // actor id (their home instance), NOT the observing account's instance.
        if
            !accountDeleted,
            let personId = row.creatorPersonId,
            let actorIdString = row.creatorActorId,
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
            bodyBlocks = []
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
            bodyBlocks = []
        } else {
            // Normal comments render through `bodyView` (MarkdownBodyView) from
            // the parsed block tree; the legacy attributed `body` is unused here.
            let bodyMarkdown = row.body ?? ""
            body = NSAttributedString()
            bodyBlocks = MarkdownBlockCache.shared.blocks(for: bodyMarkdown)
        }

        // Link preview cards under the body, capped to keep long comments tidy.
        // Empty for deleted/removed placeholders (their block tree is empty).
        linkPreviews = bodyBlocks.commentLinkPreviews(limit: 3)
        self.fetchLinkEmbeds = fetchLinkEmbeds

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

        // MARK: Subtitle (age · saved)

        voteStatus = {
            switch row.voteStatus {
            case 1: return .up
            case 0: return .down
            default: return .neutral
            }
        }()
        score = row.score
        upvoteActiveColor = appearance.general.upvoteButtonActiveColor
        downvoteActiveColor = appearance.general.downvoteButtonActiveColor

        // MARK: Score pill attributed text

        // Build the pill once in the VM so (a) the font scales with Dynamic Type
        // via the same `scaledMonospaceDigitSystemFont` used for the subtitle, and
        // (b) neutral comments still show a score (no fill, secondaryLabel color).
        // "Load more" rows and deleted/removed comments carry no meaningful score.
        let hideScore = isDeleted || isRemoved
        if !hideScore, row.moreChildCount == nil {
            // Neutral: secondaryLabel, regular weight (matches the pre-Task-5
            // subtitle appearance). Voted: white on the vote-token fill, bold so
            // the number reads heavier against the colored background.
            let isVoted = row.voteStatus == 1 || row.voteStatus == 0
            let pillFont = UIFont.scaledMonospaceDigitSystemFont(
                style: .body,
                relativeSize: -1 + textSizeAdjustment,
                weight: isVoted ? .bold : .regular
            )
            let pillColor: UIColor = isVoted ? VoteFillStyle.filledGlyphColor : .secondaryLabel
            let pillAttributes: [NSAttributedString.Key: Any] = [
                .font: pillFont,
                .foregroundColor: pillColor,
            ]
            let glyphName: String
            switch row.voteStatus {
            case 0: glyphName = "arrow.down"
            default: glyphName = "arrow.up"
            }
            let text = NSMutableAttributedString()
            if let image = UIImage(systemName: glyphName) {
                text.append(NSAttributedString.symbol(from: image, attributes: pillAttributes))
                text.append(NSAttributedString(string: " ", attributes: pillAttributes))
            }
            text.append(NSAttributedString(
                string: UpvotesFormatter.string(from: row.score),
                attributes: pillAttributes
            ))
            scorePillText = text

            // Voted: fill with the vote-token color; neutral: no fill (clear bg).
            switch row.voteStatus {
            case 1: scorePillFillColor = appearance.general.upvoteButtonActiveColor
            case 0: scorePillFillColor = appearance.general.downvoteButtonActiveColor
            default: scorePillFillColor = nil
            }
        } else {
            scorePillText = nil
            scorePillFillColor = nil
        }

        let space = NSAttributedString(string: "  ", attributes: secondaryAttributes)
        var subtitlePieces: [NSAttributedString] = []
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
        if let newCount = collapsedNewDescendantCount, newCount > 0 {
            self.collapsedNewDescendantCount = newCount
        } else {
            self.collapsedNewDescendantCount = nil
        }

        // MARK: Accessibility

        if isMore {
            subtitleAccessibilityLabel = nil
            collapseAccessibilityHint = NSLocalizedString(
                "Loads more replies",
                comment: "VoiceOver hint for the load-more-replies row"
            )
        } else {
            // The subtitle element carries comment metadata (age, depth,
            // collapsed and moderation state) for VoiceOver — the visible run
            // is icon glyphs it cannot pronounce. Score is spoken via the
            // score-pill accessibility label instead (so voted comments read
            // the score exactly once). The author (a link) and body are read
            // as their own elements.
            var pieces: [String] = []
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
                if let newCount = collapsedNewDescendantCount, newCount > 0 {
                    pieces.append(String(
                        format: NSLocalizedString(
                            "%lld new",
                            comment: "VoiceOver: count of new replies hidden under a collapsed comment"
                        ),
                        newCount
                    ))
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
            if isNew {
                pieces.append(NSLocalizedString(
                    "New comment, posted after your last visit",
                    comment: "VoiceOver: comment is new since the user's last visit"
                ))
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
