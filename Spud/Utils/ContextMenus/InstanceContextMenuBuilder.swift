//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// The per-screen action surface an `InstanceContextMenuBuilder` menu drives.
/// Search's `.instance` result rows conform so a long-press instance gets a
/// small, directory-appropriate action set: unlike the other four result
/// kinds, an instance isn't a per-viewer server entity (it's a client-side
/// Lemmy Explorer directory row), so there's no subscribe/vote/save/block
/// state to expose here.
@MainActor
protocol InstanceContextMenuHost: UIViewController {
    /// Opens the in-app instance screen. Mirrors the plain row tap.
    func instanceOpen(_ result: SearchInstanceResult)
    /// Copies the instance's `https://<baseurl>` URL to the pasteboard.
    func instanceCopyLink(_ result: SearchInstanceResult)
    /// Shares the instance's `https://<baseurl>` URL.
    func instanceShare(_ result: SearchInstanceResult)
    /// Presents the login flow targeted at this instance, so a signed-out (or
    /// already-signed-in-elsewhere) user can add an account here without first
    /// opening the instance screen and finding "Log in" there.
    func instanceAddAccount(_ result: SearchInstanceResult)
}

/// Builds the long-press menu for a Search `.instance` result: Open, Copy
/// Link, Share, and Add Account Here. Pure: every action calls back into
/// `host`; the builder performs no side effects itself.
@MainActor
enum InstanceContextMenuBuilder {
    static func menu(for result: SearchInstanceResult, host: InstanceContextMenuHost) -> UIMenu {
        let openAction = UIAction(
            title: NSLocalizedString("Open", comment: "Context-menu action to open an instance"),
            image: UIImage(systemName: "arrow.up.forward.app")
        ) { [weak host] _ in host?.instanceOpen(result) }

        let copyLinkAction = UIAction(
            title: NSLocalizedString("Copy Link", comment: "Context-menu action to copy an instance's link"),
            image: UIImage(systemName: "link")
        ) { [weak host] _ in host?.instanceCopyLink(result) }

        let shareAction = UIAction(
            title: NSLocalizedString("Share", comment: "Context-menu action to share an instance"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak host] _ in host?.instanceShare(result) }

        let openGroup = UIMenu(options: .displayInline, children: [openAction, copyLinkAction, shareAction])

        let addAccountAction = UIAction(
            title: NSLocalizedString("Add Account Here", comment: "Context-menu action to add an account on an instance"),
            image: UIImage(systemName: "person.badge.plus")
        ) { [weak host] _ in host?.instanceAddAccount(result) }
        let addAccountGroup = UIMenu(options: .displayInline, children: [addAccountAction])

        return UIMenu(title: "", children: [openGroup, addAccountGroup])
    }
}
