//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
import UIKit
@testable import Spud

/// Covers the shared `PostAuthorStatus` badge builder: the ordered pill set, the
/// low-noise list warning gate, `isDeleted`, the VoiceOver phrasing, and its
/// construction from both post read-row types. Crucially, it asserts the pills
/// match the comment builder (`PostDetailCommentViewModel`) for the shared
/// statuses so a post and a comment by the same author render identically.
@MainActor
struct PostAuthorStatusTests {
    // MARK: - Helpers

    /// A status with every flag set, for exercising the full ordered badge set.
    private func fullStatus() -> PostAuthorStatus {
        PostAuthorStatus(
            isModerator: true,
            isAdmin: true,
            isBot: true,
            isSiteBanned: true,
            banExpires: nil,
            isBannedFromCommunity: true,
            isDeleted: true
        )
    }

    /// The comment builder's badge set for the same shared statuses (not OP, not
    /// distinguished), to prove the two surfaces agree.
    private func commentBadges(
        isModerator: Bool = false,
        isAdmin: Bool = false,
        isBot: Bool = false,
        isBannedFromCommunity: Bool = false,
        isSiteBanned: Bool = false
    ) -> [AuthorBadge] {
        let row = PostDetailCommentRow(
            id: 1,
            position: 1,
            depth: 1,
            serverCommentId: 1,
            body: "body",
            originalCommentUrl: "https://lemmy.world/comment/1",
            score: 1,
            voteStatus: nil,
            isSaved: false,
            isRemoved: false,
            isDistinguished: false,
            isDeleted: false,
            isCreatorModerator: isModerator,
            isCreatorAdmin: isAdmin,
            isCreatorBannedFromCommunity: isBannedFromCommunity,
            isCreatorBlocked: false,
            isCreatorSiteBanned: isSiteBanned,
            isCreatorBot: isBot,
            isCreatorAccountDeleted: false,
            removedReason: nil,
            published: Date(),
            creatorName: "alice",
            creatorPersonId: 1,
            creatorActorId: "https://lemmy.world",
            moreChildCount: nil,
            moreParentId: nil
        )
        let appearance = AppearanceService(preferencesService: PreferencesService.ephemeral())
        // postCreatorPersonId nil => never OP, so the comment badges hold only
        // the shared role/status pills.
        return PostDetailCommentViewModel(row: row, appearance: appearance).badges
    }

    // MARK: - Ordered badge set

    @Test
    func badges_areOrderedWithExpectedAppearance() {
        let badges = fullStatus().badges
        #expect(badges == [
            AuthorBadge(text: "MOD", symbolName: nil, usesAccent: false, color: .systemGreen, solid: false),
            AuthorBadge(text: "ADMIN", symbolName: nil, usesAccent: false, color: .systemIndigo, solid: false),
            AuthorBadge(text: "BOT", symbolName: "cpu", usesAccent: false, color: .systemGray, solid: false),
            AuthorBadge(text: "BANNED", symbolName: "person.fill.xmark", usesAccent: false, color: .systemRed, solid: false),
            AuthorBadge(text: "SUSPENDED", symbolName: "person.fill.xmark", usesAccent: false, color: .systemRed, solid: false),
        ])
    }

    @Test
    func badges_emptyWhenNoStatus() {
        let status = PostAuthorStatus(
            isModerator: false, isAdmin: false, isBot: false,
            isSiteBanned: false, banExpires: nil, isBannedFromCommunity: false, isDeleted: false
        )
        #expect(status.badges.isEmpty)
    }

    // MARK: - Parity with the comment builder

    @Test
    func badges_matchCommentBuilderForSharedStatuses() {
        // The full shared set.
        #expect(fullStatus().badges == commentBadges(
            isModerator: true, isAdmin: true, isBot: true, isBannedFromCommunity: true, isSiteBanned: true
        ))

        // And each status in isolation, to catch any per-pill divergence.
        #expect(status(mod: true).badges == commentBadges(isModerator: true))
        #expect(status(admin: true).badges == commentBadges(isAdmin: true))
        #expect(status(bot: true).badges == commentBadges(isBot: true))
        #expect(status(communityBanned: true).badges == commentBadges(isBannedFromCommunity: true))
        #expect(status(siteBanned: true).badges == commentBadges(isSiteBanned: true))
    }

    // MARK: - List warning gate

    @Test
    func showsListWarningIcon_onlyForBans() {
        #expect(status(siteBanned: true).showsListWarningIcon == true)
        #expect(status(communityBanned: true).showsListWarningIcon == true)

        // Benign roles never raise the low-noise list marker.
        #expect(status(mod: true).showsListWarningIcon == false)
        #expect(status(admin: true).showsListWarningIcon == false)
        #expect(status(bot: true).showsListWarningIcon == false)

        let warning = status(siteBanned: true)
        #expect(warning.listWarningSymbolName == "person.fill.xmark")
        #expect(warning.listWarningTint == .systemRed)
    }

    // MARK: - Deleted passthrough

    @Test
    func isDeleted_passesThrough() {
        #expect(status().isDeleted == false)
        #expect(PostAuthorStatus(
            isModerator: false, isAdmin: false, isBot: false,
            isSiteBanned: false, banExpires: nil, isBannedFromCommunity: false, isDeleted: true
        ).isDeleted == true)
    }

    // MARK: - Suspension status text (PersonFormatter.banStatus)

    @Test
    func suspensionStatusText_usesBanStatusFormatter() {
        #expect(status().suspensionStatusText == nil)
        #expect(status(siteBanned: true).suspensionStatusText == PersonFormatter.banStatus(isBanned: true, banExpires: nil))

        let expiry = Date(timeIntervalSince1970: 2_000_000_000)
        let temp = PostAuthorStatus(
            isModerator: false, isAdmin: false, isBot: false,
            isSiteBanned: true, banExpires: expiry, isBannedFromCommunity: false, isDeleted: false
        )
        #expect(temp.suspensionStatusText == PersonFormatter.banStatus(isBanned: true, banExpires: expiry))
    }

    // MARK: - Accessibility phrases

    @Test
    func accessibilityPhrases_areOrderedAndSpoken() {
        #expect(fullStatus().accessibilityPhrases == [
            "moderator",
            "admin",
            "bot account",
            "banned from this community",
            "suspended site-wide",
        ])
        #expect(status().accessibilityPhrases.isEmpty)
    }

    // MARK: - Construction from both row types

    @Test
    func constructibleFromPostListRow() {
        let expiry = Date(timeIntervalSince1970: 2_000_000_000)
        let row = makePostListRow(
            isCreatorModerator: true,
            isCreatorAdmin: true,
            isCreatorBannedFromCommunity: true,
            isCreatorSiteBanned: true,
            creatorBanExpires: expiry,
            isCreatorBot: true,
            isCreatorAccountDeleted: true
        )
        let status = PostAuthorStatus(row: row)
        #expect(status == fullStatusWithExpiry(expiry))
        #expect(status.badges == fullStatus().badges)
    }

    @Test
    func constructibleFromPostDetailHeaderRow() {
        let expiry = Date(timeIntervalSince1970: 2_000_000_000)
        let header = makeHeaderRow(
            isCreatorModerator: true,
            isCreatorAdmin: true,
            isCreatorBannedFromCommunity: true,
            isCreatorSiteBanned: true,
            creatorBanExpires: expiry,
            isCreatorBot: true,
            isCreatorAccountDeleted: true
        )
        let status = PostAuthorStatus(header: header)
        #expect(status == fullStatusWithExpiry(expiry))
        #expect(status.badges == fullStatus().badges)
    }

    // MARK: - Builders

    private func fullStatusWithExpiry(_ expiry: Date) -> PostAuthorStatus {
        PostAuthorStatus(
            isModerator: true,
            isAdmin: true,
            isBot: true,
            isSiteBanned: true,
            banExpires: expiry,
            isBannedFromCommunity: true,
            isDeleted: true
        )
    }

    private func status(
        mod: Bool = false,
        admin: Bool = false,
        bot: Bool = false,
        siteBanned: Bool = false,
        communityBanned: Bool = false
    ) -> PostAuthorStatus {
        PostAuthorStatus(
            isModerator: mod,
            isAdmin: admin,
            isBot: bot,
            isSiteBanned: siteBanned,
            banExpires: nil,
            isBannedFromCommunity: communityBanned,
            isDeleted: false
        )
    }

    private func makePostListRow(
        isCreatorModerator: Bool,
        isCreatorAdmin: Bool,
        isCreatorBannedFromCommunity: Bool,
        isCreatorSiteBanned: Bool,
        creatorBanExpires: Date?,
        isCreatorBot: Bool,
        isCreatorAccountDeleted: Bool
    ) -> PostListRow {
        PostListRow(
            id: 1,
            serverPostId: 1,
            title: "t",
            body: nil,
            originalPostUrl: "https://lemmy.world/post/1",
            url: nil,
            thumbnailUrl: nil,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            altText: nil,
            communityName: "news",
            communityActorId: "https://lemmy.world/c/news",
            serverCommunityId: 1,
            creatorPersonId: 1,
            creatorName: "alice",
            creatorActorId: "https://lemmy.world/u/alice",
            score: 1,
            numberOfComments: 0,
            voteStatus: nil,
            isRead: false,
            isSaved: false,
            isRemoved: false,
            isLocked: false,
            isFeaturedCommunity: false,
            isFeaturedLocal: false,
            isDeleted: false,
            isNsfw: false,
            isCreatorModerator: isCreatorModerator,
            isCreatorAdmin: isCreatorAdmin,
            isCreatorBannedFromCommunity: isCreatorBannedFromCommunity,
            isCreatorSiteBanned: isCreatorSiteBanned,
            creatorBanExpires: creatorBanExpires,
            isCreatorBot: isCreatorBot,
            isCreatorAccountDeleted: isCreatorAccountDeleted,
            published: Date()
        )
    }

    private func makeHeaderRow(
        isCreatorModerator: Bool,
        isCreatorAdmin: Bool,
        isCreatorBannedFromCommunity: Bool,
        isCreatorSiteBanned: Bool,
        creatorBanExpires: Date?,
        isCreatorBot: Bool,
        isCreatorAccountDeleted: Bool
    ) -> PostDetailHeaderRow {
        PostDetailHeaderRow(
            id: 1,
            serverPostId: 1,
            title: "t",
            body: nil,
            originalPostUrl: "https://lemmy.world/post/1",
            url: nil,
            thumbnailUrl: nil,
            imageWidth: nil,
            imageHeight: nil,
            urlEmbedTitle: nil,
            urlEmbedDescription: nil,
            altText: nil,
            communityName: "news",
            communityActorId: "https://lemmy.world/c/news",
            serverCommunityId: 1,
            creatorName: "alice",
            creatorPersonId: 1,
            creatorActorId: "https://lemmy.world/u/alice",
            score: 1,
            numberOfComments: 0,
            voteStatus: nil,
            isSaved: false,
            isRemoved: false,
            isLocked: false,
            isFeaturedCommunity: false,
            isFeaturedLocal: false,
            isDeleted: false,
            isNsfw: false,
            isCreatorModerator: isCreatorModerator,
            isCreatorAdmin: isCreatorAdmin,
            isCreatorBannedFromCommunity: isCreatorBannedFromCommunity,
            isCreatorSiteBanned: isCreatorSiteBanned,
            creatorBanExpires: creatorBanExpires,
            isCreatorBot: isCreatorBot,
            isCreatorAccountDeleted: isCreatorAccountDeleted,
            published: Date()
        )
    }
}
