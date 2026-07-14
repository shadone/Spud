//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import UIKit

/// The per-screen action surface a `PostContextMenuBuilder` menu drives. Any
/// screen that shows a post row (the feed, Search) conforms so it gets the
/// identical long-press menu. Refines the shared vote/save/remind dispatch
/// protocols so vote/save/Remind-Me route through the same outbox/ReminderService
/// paths on every screen.
///
/// The four `…Submenu` members have default implementations (below) so a host
/// only overrides the ones it supports: the feed overrides cross-post-siblings
/// and moderation (feed-only state); Search inherits their nil defaults.
@MainActor
protocol PostContextMenuHost: PostSaveDispatching, PostReminderDispatching {
    /// The feed row for `serverPostId`, or nil if it isn't currently loaded.
    func postContextRow(forServerPostId serverPostId: Int64) -> PostListRow?

    /// The whole-post fields for the "Remind Me…" menu at `serverPostId`, or
    /// nil if the row isn't currently loaded. Feeds the shared
    /// `postRemindMeSubmenu` default below (mirrors each screen's existing
    /// per-row `remindMeMenuTarget` helper, just named at the shared-protocol
    /// level so the default extension can call it).
    func remindMeMenuTarget(serverPostId: Int64) -> RemindMeMenuTarget?

    /// Votes on the post. Re-declared here even though `PostVoteDispatching`
    /// already supplies a default implementation in its extension: a protocol
    /// extension method that isn't also a requirement is dispatched
    /// STATICALLY, so calling `host.vote(...)` through a
    /// `PostContextMenuHost`-typed value (as the builder below does) would
    /// always run the shared default and silently ignore a conformer's own
    /// override (e.g. a test double recording the call) — declaring it here
    /// makes it part of `PostContextMenuHost`'s witness table, so dispatch
    /// resolves to whichever implementation the concrete conformer provides.
    /// Every existing conformer (the feed) already satisfies this via the
    /// inherited `PostVoteDispatching` default, so this is a no-op for them.
    func vote(serverPostId: Int64, action: VoteStatus.Action) async

    func postReply(serverPostId: Int64)
    func postShare(serverPostId: Int64)
    func postCrossPost(serverPostId: Int64)
    func postVisitCommunity(serverPostId: Int64)
    func postViewAuthor(serverPostId: Int64)
    func postHide(serverPostId: Int64)
    func postBlockAuthor(serverPostId: Int64)
    func postReport(serverPostId: Int64)
    /// Mutes the post's community for `duration` (client-local). Called by the
    /// default `postMuteCommunitySubmenu`.
    func postMuteCommunity(serverPostId: Int64, duration: MuteDuration)

    /// The "Also posted in" cross-post jump submenu, or nil when the post has no
    /// collapsed siblings. Default: nil (Search has no cross-post grouping).
    func postCrossPostSiblingsSubmenu(serverPostId: Int64) -> UIMenu?
    /// The moderation submenu, or nil when the viewer doesn't moderate the
    /// community. Default: nil (Search has no moderation context).
    func postModerationSubmenu(serverPostId: Int64) -> UIMenu?
}

@MainActor
extension PostContextMenuHost {
    func postCrossPostSiblingsSubmenu(serverPostId _: Int64) -> UIMenu? {
        nil
    }

    func postModerationSubmenu(serverPostId _: Int64) -> UIMenu? {
        nil
    }

    /// The "Remind Me…" submenu, built from the shared `PostReminderDispatching`
    /// target, or nil when the row isn't loaded. Shared across hosts.
    func postRemindMeSubmenu(serverPostId: Int64) -> UIMenu? {
        guard let target = remindMeMenuTarget(serverPostId: serverPostId) else { return nil }
        return makeRemindMeMenu(for: target)
    }

    /// The "Mute c/…" duration submenu, or nil when the community can't be
    /// resolved. Shared across hosts (muting is client-local).
    func postMuteCommunitySubmenu(serverPostId: Int64) -> UIMenu? {
        guard
            let row = postContextRow(forServerPostId: serverPostId),
            let communityName = row.communityName.isEmpty ? nil : row.communityName,
            row.communityActorId != nil
        else { return nil }
        let actions = MuteDuration.allCases.map { duration in
            UIAction(title: duration.menuTitle) { [weak self] _ in
                self?.postMuteCommunity(serverPostId: serverPostId, duration: duration)
            }
        }
        return UIMenu(
            title: String(format: NSLocalizedString("Mute %@", comment: "Context-menu action to mute a community; %@ is the c/ community handle"), "c/\(communityName)"),
            image: UIImage(systemName: "bell.slash"),
            children: actions
        )
    }
}

/// Builds the shared post long-press menu. The single source of truth for the
/// post context menu's structure, used by the feed and Search so the two never
/// drift. Pure: every action calls back into `host`; the builder performs no
/// side effects itself.
@MainActor
enum PostContextMenuBuilder {
    static func menu(
        forServerPostId serverPostId: Int64,
        host: PostContextMenuHost,
        upvoteIcon: UIImage?,
        downvoteIcon: UIImage?
    ) -> UIMenu {
        let upvoteAction = UIAction(
            title: NSLocalizedString("Upvote", comment: ""),
            image: upvoteIcon
        ) { [weak host] _ in
            Task { await host?.vote(serverPostId: serverPostId, action: .upvote) }
        }
        let downvoteAction = UIAction(
            title: NSLocalizedString("Downvote", comment: ""),
            image: downvoteIcon
        ) { [weak host] _ in
            Task { await host?.vote(serverPostId: serverPostId, action: .downvote) }
        }

        let isSaved = host.postContextRow(forServerPostId: serverPostId)?.isSaved ?? false
        let saveAction = UIAction(
            title: isSaved
                ? NSLocalizedString("Unsave", comment: "Context-menu action to unsave a post")
                : NSLocalizedString("Save", comment: "Context-menu action to save a post"),
            image: UIImage(systemName: isSaved ? "bookmark.slash" : "bookmark")
        ) { [weak host] _ in
            host?.toggleSaved(serverPostId: serverPostId)
        }

        let replyAction = UIAction(
            title: NSLocalizedString("Reply", comment: "Context-menu action to reply to a post"),
            image: UIImage(systemName: "arrowshape.turn.up.left")
        ) { [weak host] _ in host?.postReply(serverPostId: serverPostId) }

        let shareAction = UIAction(
            title: NSLocalizedString("Share", comment: "Context-menu action to share a post"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak host] _ in host?.postShare(serverPostId: serverPostId) }

        let crossPostAction = UIAction(
            title: NSLocalizedString("Cross-post", comment: "Context-menu action to re-share a post to another community"),
            image: UIImage(systemName: "arrow.triangle.branch")
        ) { [weak host] _ in host?.postCrossPost(serverPostId: serverPostId) }

        let row = host.postContextRow(forServerPostId: serverPostId)

        let visitCommunityAction = UIAction(
            title: String(
                format: NSLocalizedString("Visit %@", comment: "Context-menu action to open a post's community; %@ is the c/ community handle"),
                row.map { "c/\($0.communityName)" } ?? NSLocalizedString("community", comment: "Generic community noun")
            ),
            image: UIImage(systemName: "person.3")
        ) { [weak host] _ in host?.postVisitCommunity(serverPostId: serverPostId) }

        let viewAuthorAction = UIAction(
            title: row?.creatorName.map {
                String(format: NSLocalizedString("View %@", comment: "Context-menu action to open a post author's profile; %@ is the u/ author handle"), "u/\($0)")
            } ?? NSLocalizedString("View author", comment: "Context-menu action to open a post author's profile"),
            image: UIImage(systemName: "person.crop.circle")
        ) { [weak host] _ in host?.postViewAuthor(serverPostId: serverPostId) }

        let hideAction = UIAction(
            title: NSLocalizedString("Hide", comment: "Context-menu action to hide a post from the feed"),
            image: UIImage(systemName: "eye.slash")
        ) { [weak host] _ in host?.postHide(serverPostId: serverPostId) }

        let blockAction = UIAction(
            title: row?.creatorName.map {
                String(format: NSLocalizedString("Block %@", comment: "Context-menu action to block a post author; %@ is the u/ author handle"), "u/\($0)")
            } ?? NSLocalizedString("Block author", comment: "Context-menu action to block a post author"),
            image: UIImage(systemName: "hand.raised"),
            attributes: .destructive
        ) { [weak host] _ in host?.postBlockAuthor(serverPostId: serverPostId) }

        let reportAction = UIAction(
            title: NSLocalizedString("Report", comment: "Context-menu action to report a post"),
            image: UIImage(systemName: "flag"),
            attributes: .destructive
        ) { [weak host] _ in host?.postReport(serverPostId: serverPostId) }

        var voteChildren: [UIMenuElement] = [upvoteAction, downvoteAction, saveAction]
        if let remindMe = host.postRemindMeSubmenu(serverPostId: serverPostId) {
            voteChildren.append(remindMe)
        }
        let voteGroup = UIMenu(options: .displayInline, children: voteChildren)
        let shareGroup = UIMenu(options: .displayInline, children: [replyAction, shareAction, crossPostAction])

        var navChildren: [UIMenuElement] = [visitCommunityAction, viewAuthorAction]
        if let crossPostMenu = host.postCrossPostSiblingsSubmenu(serverPostId: serverPostId) {
            navChildren.append(crossPostMenu)
        }
        let navGroup = UIMenu(options: .displayInline, children: navChildren)

        var hideChildren: [UIMenuElement] = [hideAction]
        if let muteMenu = host.postMuteCommunitySubmenu(serverPostId: serverPostId) {
            hideChildren.append(muteMenu)
        }
        let hideGroup = UIMenu(options: .displayInline, children: hideChildren)
        let safetyGroup = UIMenu(options: .displayInline, children: [blockAction, reportAction])

        var children: [UIMenuElement] = [voteGroup, shareGroup, navGroup, hideGroup]
        if let modMenu = host.postModerationSubmenu(serverPostId: serverPostId) {
            children.append(modMenu)
        }
        children.append(safetyGroup)
        return UIMenu(title: "", children: children)
    }
}
