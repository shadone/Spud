//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import UIKit

/// The per-screen action surface a `UserContextMenuBuilder` menu drives.
/// Search's `.user` result rows conform so a long-press user gets the same
/// primary actions as `PersonViewController`'s header context menu (Copy
/// handle, Block/Unblock), plus Open profile and Share to reach parity with
/// the other search result menus' item set.
@MainActor
protocol UserContextMenuHost: UIViewController {
    /// Opens the person's profile screen. Mirrors the plain row tap.
    func userOpen(_ result: SearchUserResult)
    /// Copies the `@name@instance` handle to the pasteboard, mirroring
    /// `PersonViewController`'s "Copy handle" header action.
    func userCopyHandle(_ result: SearchUserResult)
    /// Shares the person's canonical profile URL.
    func userShare(_ result: SearchUserResult)
    /// Blocks or unblocks the person on the signed-in account. The host gates
    /// on sign-in and presents a destructive confirmation before blocking;
    /// unblocking is not destructive and needs none.
    func userSetBlocked(_ result: SearchUserResult, blocked: Bool)
}

/// Builds the long-press menu for a Search `.user` result. Mirrors
/// `PersonViewController`'s header context menu (Copy handle, Block/Unblock)
/// plus Open profile and Share, the item set spec §3.4 calls for.
///
/// `isBlocked` is passed in by the caller rather than resolved through a host
/// callback (contrast `CommunityContextMenuHost.communityIsMuted`, a cheap
/// synchronous client-local read): the account's block list is only knowable
/// via a network round trip (`LemmyService.fetchBlockedList`, backed by
/// `getSite`), which a menu-build closure must not perform. `SearchViewController`
/// has no cheap sync lookup for it (see its `UserContextMenuHost` conformance),
/// so it always passes `false` -- meaning Search only ever offers "Block user",
/// never "Unblock", matching the design spec's fallback for when block state
/// can't be determined without a fetch.
///
/// Pure: every action calls back into `host`; the builder performs no side
/// effects itself.
@MainActor
enum UserContextMenuBuilder {
    static func menu(for result: SearchUserResult, isBlocked: Bool, host: UserContextMenuHost) -> UIMenu {
        let openAction = UIAction(
            title: NSLocalizedString("Open profile", comment: "Context-menu action to open a user's profile"),
            image: UIImage(systemName: "person.crop.circle")
        ) { [weak host] _ in host?.userOpen(result) }

        let copyHandleAction = UIAction(
            title: NSLocalizedString("Copy handle", comment: "Context-menu action to copy a user's @user@instance handle"),
            image: UIImage(systemName: "doc.on.doc")
        ) { [weak host] _ in host?.userCopyHandle(result) }

        let shareAction = UIAction(
            title: NSLocalizedString("Share", comment: "Context-menu action to share a user's profile"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak host] _ in host?.userShare(result) }

        let openGroup = UIMenu(options: .displayInline, children: [openAction, copyHandleAction, shareAction])

        let blockAction = UIAction(
            title: isBlocked
                ? NSLocalizedString("Unblock user", comment: "Context-menu action to unblock a user")
                : NSLocalizedString("Block user", comment: "Context-menu action to block a user"),
            image: UIImage(systemName: isBlocked ? "hand.raised.slash" : "hand.raised"),
            attributes: isBlocked ? [] : .destructive
        ) { [weak host] _ in host?.userSetBlocked(result, blocked: !isBlocked) }
        let blockGroup = UIMenu(options: .displayInline, children: [blockAction])

        return UIMenu(title: "", children: [openGroup, blockGroup])
    }
}
