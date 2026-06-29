//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The decision of how to open an external link, given connectivity, whether a
/// saved web archive exists for the link, and the user's open-external-links
/// preference.
///
/// Pure data: ``resolveOpenStrategy(isOnline:hasArchive:preference:)`` computes
/// it from inputs alone (no WebKit, no UIKit), so the routing rules are
/// unit-testable without standing up a `WKWebView` or a simulator.
enum OpenLinkStrategy: Equatable {
    /// Present the offline reader (`OfflineWebArchiveReaderViewController`) with
    /// the stored `.webarchive`. Only chosen when offline AND an archive exists.
    case archiveReader

    /// Open in the in-app browser (`SFSafariViewController`) — the
    /// `.safariViewController` preference, online.
    case safari

    /// Open in the system default browser — the `.browser` preference, online.
    case browser

    /// Offline with no saved archive: a live load can't succeed
    /// (`SFSafariViewController` would show a blank page / error). The caller
    /// surfaces a brief toast instead of presenting a broken browser.
    case offlineNoArchive
}

/// Decide how to open an external link.
///
/// The guiding rule: **online always prefers the live page.** A saved archive is
/// only a fallback for when there is no connection — when online the live page is
/// strictly better (it's current, fully interactive, and not a frozen snapshot),
/// so the archive is ignored regardless of whether one exists.
///
/// - When **online**: honour the user's `preference` (in-app Safari vs. system
///   browser); the archive (if any) is not consulted.
/// - When **offline + an archive exists**: open the saved snapshot in the in-app
///   reader (`.archiveReader`).
/// - When **offline + no archive**: `.offlineNoArchive`. The live path can't load
///   offline, and presenting an empty/error browser is a poor experience, so the
///   caller shows a "this page isn't saved for offline" toast and does not
///   present a browser at all.
///
/// - Parameters:
///   - isOnline: Current network reachability (`ReachabilityMonitoring.isOnline`).
///   - hasArchive: Whether a saved web archive exists for the (sanitized) link.
///   - preference: The user's open-external-links preference.
/// - Returns: The strategy the caller should act on.
func resolveOpenStrategy(
    isOnline: Bool,
    hasArchive: Bool,
    preference: Preferences.OpenExternalLink
) -> OpenLinkStrategy {
    guard !isOnline else {
        // Online: the live page is always preferable to a snapshot — ignore any
        // saved archive and route by the user's preference.
        switch preference {
        case .safariViewController:
            return .safari
        case .browser:
            return .browser
        }
    }

    // Offline: a saved snapshot is the only thing that can render.
    return hasArchive ? .archiveReader : .offlineNoArchive
}
