//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import UIKit

/// The per-screen action surface a `CommunityContextMenuBuilder` menu drives.
/// Search's `.community` result rows conform so they get the same actions as
/// Discover's SwiftUI `CommunityContextMenu` (`Spud/Scenes/Discover/CommunityContextMenu.swift`),
/// adapted to a live per-viewer `SearchCommunityResult` (server subscribe/block
/// state) rather than Discover's Explorer-directory row (which has no
/// per-viewer relationship data and tracks subscriptions client-side instead).
@MainActor
protocol CommunityContextMenuHost: UIViewController {
    func communityOpen(_ result: SearchCommunityResult)
    func communitySetSubscribed(_ result: SearchCommunityResult, subscribed: Bool)
    /// Whether `result`'s community is currently muted (client-local). Called
    /// at menu-build time to decide between the Mute submenu and Unmute action.
    func communityIsMuted(_ result: SearchCommunityResult) -> Bool
    func communityMute(_ result: SearchCommunityResult, duration: MuteDuration)
    func communityUnmute(_ result: SearchCommunityResult)
    /// Shares the community's `communityUrl`.
    func communityShare(_ result: SearchCommunityResult)
    /// Copies the community's `communityUrl` to the pasteboard.
    func communityCopyLink(_ result: SearchCommunityResult)
    func communityBlock(_ result: SearchCommunityResult)
}

/// Builds the community long-press menu for a Search `.community` result. Mirrors
/// Discover's SwiftUI `CommunityContextMenu` item-for-item (Open, Subscribe /
/// Unsubscribe, Mute duration submenu / Unmute, Share, Copy Link, Block), ported
/// to `UIMenu`/`UIAction` for UIKit's `UIContextMenuConfiguration`. Pure: every
/// action calls back into `host`; the builder performs no side effects itself.
@MainActor
enum CommunityContextMenuBuilder {
    /// Builds the menu for `result`. `subscribedState` is the caller's RESOLVED
    /// 5-state subscribe state (`SearchViewModel.subscribeState(for:)` —
    /// persisted-DB-wins, falling back to the search response's network
    /// `followState`), not the raw network state — so the Subscribe/Unsubscribe
    /// label reflects a Pending / Requested follow the same way
    /// `CommunityHeaderView` does, rather than the lossy `result.followState`
    /// collapsing Pending down to "Subscribe".
    static func menu(
        for result: SearchCommunityResult,
        subscribedState: CommunitySubscribedState,
        host: CommunityContextMenuHost
    ) -> UIMenu {
        let openAction = UIAction(
            title: NSLocalizedString("Open Community", comment: "Context-menu action to open a community"),
            image: UIImage(systemName: "arrow.up.forward.app")
        ) { [weak host] _ in host?.communityOpen(result) }

        // `.isSubscribed` covers subscribed / pending / approvalRequired — all of
        // which show "Unsubscribe" here, matching `CommunitySubscribedState`'s own
        // definition of an active follow.
        let subscribed = subscribedState.isSubscribed
        let subscribeAction = UIAction(
            title: subscribed
                ? NSLocalizedString("Unsubscribe", comment: "Context-menu action to unsubscribe from a community")
                : NSLocalizedString("Subscribe", comment: "Context-menu action to subscribe to a community"),
            image: UIImage(systemName: subscribed ? "checkmark" : "plus")
        ) { [weak host] _ in host?.communitySetSubscribed(result, subscribed: !subscribed) }

        let openGroup = UIMenu(options: .displayInline, children: [openAction, subscribeAction])

        let muteElement: UIMenuElement
        if host.communityIsMuted(result) {
            muteElement = UIAction(
                title: NSLocalizedString("Unmute", comment: "Context-menu action to unmute a community"),
                image: UIImage(systemName: "bell")
            ) { [weak host] _ in host?.communityUnmute(result) }
        } else {
            let durationActions = MuteDuration.allCases.map { duration in
                UIAction(title: duration.menuTitle) { [weak host] _ in
                    host?.communityMute(result, duration: duration)
                }
            }
            muteElement = UIMenu(
                title: NSLocalizedString("Mute", comment: "Context-menu action to mute a community"),
                image: UIImage(systemName: "bell.slash"),
                children: durationActions
            )
        }
        let muteGroup = UIMenu(options: .displayInline, children: [muteElement])

        var shareChildren: [UIMenuElement] = []
        if URL(string: result.communityUrl) != nil {
            let shareAction = UIAction(
                title: NSLocalizedString("Share", comment: "Context-menu action to share a community"),
                image: UIImage(systemName: "square.and.arrow.up")
            ) { [weak host] _ in host?.communityShare(result) }
            let copyAction = UIAction(
                title: NSLocalizedString("Copy Link", comment: "Context-menu action to copy a community's link"),
                image: UIImage(systemName: "link")
            ) { [weak host] _ in host?.communityCopyLink(result) }
            shareChildren = [shareAction, copyAction]
        }
        let shareGroup = UIMenu(options: .displayInline, children: shareChildren)

        let blockAction = UIAction(
            title: NSLocalizedString("Block Community", comment: "Context-menu action to block a community"),
            image: UIImage(systemName: "hand.raised"),
            attributes: .destructive
        ) { [weak host] _ in host?.communityBlock(result) }
        let blockGroup = UIMenu(options: .displayInline, children: [blockAction])

        var children: [UIMenuElement] = [openGroup, muteGroup]
        if !shareChildren.isEmpty {
            children.append(shareGroup)
        }
        children.append(blockGroup)
        return UIMenu(title: "", children: children)
    }
}
