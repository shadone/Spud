//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Centralized copy + symbols for the community "Notify About New Posts"
/// follow, shared by every surface (community overflow, Search context menu,
/// Subscriptions meta rows and subscribed-list menu) so the wording can't
/// drift. `bell.badge`, not `bell`/`bell.slash` - those belong to Mute/Unmute
/// (and the Remind Me submenu), which can appear in the same menus.
enum CommunityNotifyLabel {
    /// The menu action's title, identical whether the follow is currently on
    /// or off - state is conveyed via the checkmark (`UIAction.state`) and
    /// `symbol(isNotifying:)`, not by swapping the title.
    static var title: String {
        NSLocalizedString("Notify About New Posts", comment: "Menu action to follow a community for new-post notifications")
    }

    /// The SF Symbol name for the action, filled when a follow is live.
    static func symbol(isNotifying: Bool) -> String {
        isNotifying ? "bell.badge.fill" : "bell.badge"
    }

    /// Toast shown after the follow is set.
    static var toastOn: String {
        NSLocalizedString("You'll be notified of new posts.", comment: "Toast confirming a community new-posts follow was set")
    }

    /// Toast shown after the follow is removed.
    static var toastOff: String {
        NSLocalizedString("Stopped notifying.", comment: "Toast confirming a community new-posts follow was removed")
    }
}
