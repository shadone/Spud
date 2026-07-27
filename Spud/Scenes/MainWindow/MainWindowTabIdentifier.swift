//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

/// Stable identifiers for the root tabs `MainWindow` builds with
/// `UITabBarController.setTabs(_:animated:)`.
///
/// Tabs are addressed by identifier, never by index: the system relocates
/// the search tab to the trailing edge, so an index is not a stable
/// reference to a tab. Once `setTabs` has been called, the entire legacy
/// `UITabBarController` family (`selectedIndex`, `selectedViewController`,
/// `viewControllers`, `tabBar.items[...]`) becomes a silent no-op — see the
/// doc comment directly above the `tabs` property in `UITabBarController.h`:
/// "Once set, `UITabBarController.viewControllers` and related properties
/// and methods will not be called." Reading `selectedViewController` always
/// returns nil; writing `selectedIndex` never changes the visible tab. The
/// live replacements are `tabBarController.tab(forIdentifier:)` /
/// `.selectedTab` / `.selectedTab?.viewController`.
///
/// Not nested in `MainWindow` because `MainWindowSplitViewController` (a
/// sibling file) also needs to select a root tab by identity (its
/// QuickSwitch "Browse all communities" row).
///
/// Search is absent deliberately — `UISearchTab` assigns its own system
/// identifier, available as the type property `UISearchTab.identifier`.
enum MainWindowTabIdentifier {
    static let posts = "posts"
    static let communities = "communities"
    static let inbox = "inbox"
    static let account = "account"
}
