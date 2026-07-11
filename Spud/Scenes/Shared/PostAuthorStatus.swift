//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import UIKit

/// The post author's role/status, derived from the fields a post read row
/// carries, turned into the shared ``AuthorBadge`` pills and their spoken forms.
/// The single DRY brain both post render surfaces use: the detail header renders
/// the full ``badges`` set, while the low-noise post list shows only
/// ``showsListWarningIcon``.
///
/// Mirrors the comment badge builder in `PostDetailCommentViewModel` — the same
/// pill order, colors, symbols, and VoiceOver phrasing — minus the OP badge,
/// which is meaningless on a post (a post's author *is* the original poster).
/// MOD / ADMIN pills are always tinted (never the solid "distinguished"
/// treatment a distinguished moderator comment gets), because a post carries no
/// per-post "distinguished" statement.
///
/// Sources of the underlying flags:
/// - per-community context (`isModerator` / `isAdmin` / `isBannedFromCommunity`)
///   rides on the `PostView` and is stored on the post row;
/// - site-ban / bot / deleted come from the author's `person` row
///   (`PersonRecord.isBanned` / `isBotAccount` / `isDeleted`).
struct PostAuthorStatus: Equatable {
    /// The author moderates the community this post is in (`PostView.creator_is_moderator`).
    let isModerator: Bool
    /// The author is an admin of the instance (`PostView.creator_is_admin`).
    let isAdmin: Bool
    /// The author is a bot account (`Person.bot_account`).
    let isBot: Bool
    /// The author is banned site-wide — "suspended" — on their home instance
    /// (`Person.banned`). Distinct from ``isBannedFromCommunity``.
    let isSiteBanned: Bool
    /// Expiry of a temporary site-wide ban, when known (`Person.ban_expires`).
    /// nil for a permanent ban or an unbanned author.
    let banExpires: Date?
    /// The author is banned from this specific community
    /// (`PostView.creator_banned_from_community`). Distinct from ``isSiteBanned``.
    let isBannedFromCommunity: Bool
    /// The author's account is deleted (`Person.deleted`). Not a pill: the
    /// caller renders the name as "[deleted]" and suppresses the profile link.
    let isDeleted: Bool

    /// The ordered full set of author-status pills for the detail header, in the
    /// same order and appearance as the comment builder (MOD, ADMIN, BOT,
    /// BANNED-from-community, SUSPENDED-site), minus OP.
    var badges: [AuthorBadge] {
        var result: [AuthorBadge] = []
        if isModerator {
            result.append(AuthorBadge(text: "MOD", symbolName: nil, usesAccent: false, color: .systemGreen, solid: false))
        }
        if isAdmin {
            result.append(AuthorBadge(text: "ADMIN", symbolName: nil, usesAccent: false, color: .systemIndigo, solid: false))
        }
        if isBot {
            result.append(AuthorBadge(text: "BOT", symbolName: "cpu", usesAccent: false, color: .systemGray, solid: false))
        }
        if isBannedFromCommunity {
            result.append(AuthorBadge(text: "BANNED", symbolName: "person.fill.xmark", usesAccent: false, color: .systemRed, solid: false))
        }
        if isSiteBanned {
            result.append(AuthorBadge(text: "SUSPENDED", symbolName: "person.fill.xmark", usesAccent: false, color: .systemRed, solid: false))
        }
        return result
    }

    /// Whether the low-noise post-list marker should show — ONLY for a suspended
    /// or community-banned author (never admin / mod / bot). The feed stays quiet
    /// for benign roles and flags only the "this author is banned" signal a
    /// reader scanning a list benefits from.
    var showsListWarningIcon: Bool {
        isSiteBanned || isBannedFromCommunity
    }

    /// SF Symbol for the post-list warning marker — the same glyph the SUSPENDED
    /// and BANNED pills use. Meaningful only when ``showsListWarningIcon``.
    var listWarningSymbolName: String {
        "person.fill.xmark"
    }

    /// Tint for the post-list warning marker.
    var listWarningTint: UIColor {
        .systemRed
    }

    /// A human-readable suspension status ("Banned" / "Banned · until <date>")
    /// for a render surface to show alongside the SUSPENDED pill, or nil when the
    /// author is not site-banned. Backed by the shared ``PersonFormatter/banStatus(isBanned:banExpires:)``,
    /// the same helper the profile header uses.
    var suspensionStatusText: String? {
        PersonFormatter.banStatus(isBanned: isSiteBanned, banExpires: banExpires)
    }

    /// The spoken (VoiceOver) forms of the author's statuses, in the same order
    /// as ``badges``. Mirrors the comment builder's phrasing so a post and a
    /// comment by the same author read identically. If both bans apply, prefers
    /// the "suspended site-wide" reading for VoiceOver — both are still listed.
    var accessibilityPhrases: [String] {
        var phrases: [String] = []
        if isModerator {
            phrases.append(NSLocalizedString("moderator", comment: "VoiceOver: post by a community moderator"))
        }
        if isAdmin {
            phrases.append(NSLocalizedString("admin", comment: "VoiceOver: post by an instance admin"))
        }
        if isBot {
            phrases.append(NSLocalizedString("bot account", comment: "VoiceOver: post by a bot account"))
        }
        if isBannedFromCommunity {
            phrases.append(NSLocalizedString("banned from this community", comment: "VoiceOver: author banned from the community"))
        }
        if isSiteBanned {
            phrases.append(NSLocalizedString("suspended site-wide", comment: "VoiceOver: author suspended instance-wide"))
        }
        return phrases
    }
}

extension PostAuthorStatus {
    /// Builds the author status from a feed ``PostListRow``.
    init(row: PostListRow) {
        self.init(
            isModerator: row.isCreatorModerator,
            isAdmin: row.isCreatorAdmin,
            isBot: row.isCreatorBot,
            isSiteBanned: row.isCreatorSiteBanned,
            banExpires: row.creatorBanExpires,
            isBannedFromCommunity: row.isCreatorBannedFromCommunity,
            isDeleted: row.isCreatorAccountDeleted
        )
    }

    /// Builds the author status from a post-detail ``PostDetailHeaderRow``.
    init(header: PostDetailHeaderRow) {
        self.init(
            isModerator: header.isCreatorModerator,
            isAdmin: header.isCreatorAdmin,
            isBot: header.isCreatorBot,
            isSiteBanned: header.isCreatorSiteBanned,
            banExpires: header.creatorBanExpires,
            isBannedFromCommunity: header.isCreatorBannedFromCommunity,
            isDeleted: header.isCreatorAccountDeleted
        )
    }
}
