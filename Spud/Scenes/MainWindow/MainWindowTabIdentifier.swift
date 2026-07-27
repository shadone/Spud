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
/// reference to a tab.
///
/// The rule is about staying on a SUPPORTED API, not about avoiding a live
/// bug. The doc comment above the `tabs` property in `UITabBarController.h`
/// states the contract — "Once set, `UITabBarController.viewControllers` and
/// related properties and methods will not be called." — but on this SDK
/// (Xcode 26.3 / iPhoneSimulator26.2) the legacy family still works as a
/// compatibility bridge: measured, `setTabs` implicitly selects the first
/// tab, `selectedViewController` tracks a modern `selectedTab` write, and
/// writing `selectedIndex` drives `selectedTab`. So an index-based access is
/// unsupported and may stop working, not something that is broken today.
/// Prefer the live replacements — `tabBarController.tab(forIdentifier:)` /
/// `.selectedTab` / `.selectedTab?.viewController` — and do not treat a
/// surviving legacy call site as an urgent defect.
///
/// Not nested in `MainWindow` because `MainWindowSplitViewController` (a
/// sibling file) also needs to select a root tab by identity (its
/// QuickSwitch "Browse all communities" row).
///
/// Search is absent deliberately — `UISearchTab` assigns its own system
/// identifier. Apple documents a `UISearchTab.identifier` type property for
/// reading it, but this SDK does not declare one, so the search tab is found
/// by type instead (see `MainWindow.selectSearch(query:)`).
enum MainWindowTabIdentifier {
    static let posts = "posts"
    static let communities = "communities"
    static let inbox = "inbox"
    static let account = "account"
}
