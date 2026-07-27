//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import SpudUtilKit
import Testing
import UIKit
@testable import Spud

/// Regression coverage for tab selection once `MainWindow` addresses root
/// tabs with `UITabBarController.setTabs(_:animated:)` rather than the
/// legacy `setViewControllers(_:animated:)`.
///
/// `UITabBarController.h` states, directly above the `tabs` property: "Once
/// set, `UITabBarController.viewControllers` and related properties and
/// methods will not be called" — Apple's own documented position is that
/// `selectedIndex` / `selectedViewController` / `viewControllers` are not
/// supported once `setTabs` is in use, and a caller should address tabs via
/// `tab(forIdentifier:)` / `selectedTab` instead, as this file's fixes now
/// do. A direct empirical check on the installed toolchain (Xcode 26.3.0,
/// iPhoneSimulator26.2 SDK) found the legacy accessors still function as a
/// compatibility bridge on THIS SDK snapshot (`selectedIndex = 1` and
/// `selectedViewController` correctly track `selectedTab` even after
/// `setTabs`) — so relying on them isn't reproducibly broken today, but it
/// is unsupported, undocumented-to-keep-working, and one SDK update away
/// from silently regressing exactly as a "removed API" would. These tests
/// lock in the identifier-based replacement rather than re-asserting a
/// specific breakage that doesn't currently reproduce.
///
/// `SplitTabResolverTests` only ever injects `selected` directly; these
/// tests build a real `UITabBarController` with `setTabs` and drive it
/// through its public selection API, the same way `MainWindow` and
/// `MainWindowSplitViewController` do in production.
@MainActor
struct MainWindowTabSelectionTests {
    /// Extends `SplitTabResolverTests` to the LIVE property path it doesn't
    /// cover: selecting the Posts tab on a real `setTabs`-built
    /// `UITabBarController` and resolving via `selectedTab?.viewController`
    /// (what `pushIntoCurrentContext` actually reads) must still classify as
    /// `.postsSplit`.
    @Test
    func resolvesPostsSplitFromLiveSelectedTab() {
        let posts = UISplitViewController(style: .doubleColumn)
        let postsTab = UITab(
            title: "Posts",
            image: nil,
            identifier: MainWindowTabIdentifier.posts
        ) { _ in posts }
        let communitiesNav = UINavigationController(rootViewController: UIViewController())
        let communitiesTab = UITab(
            title: "Communities",
            image: nil,
            identifier: MainWindowTabIdentifier.communities
        ) { _ in communitiesNav }

        let tabBarController = UITabBarController()
        tabBarController.setTabs([postsTab, communitiesTab], animated: false)
        tabBarController.selectedTab = postsTab

        let target = SplitTabResolver.target(
            for: tabBarController.selectedTab?.viewController,
            postsSplit: posts
        )
        guard case .postsSplit = target else {
            Issue.record("expected .postsSplit, got \(target)")
            return
        }
    }

    /// Extends `SplitTabResolverTests` to the LIVE property path for a
    /// non-Posts selection too: with Communities selected, resolving via
    /// `selectedTab?.viewController` must classify as `.plainNav` (not
    /// `.postsSplit` and not `.none`), matching what `pushIntoCurrentContext`
    /// needs to route a detail push into the Communities tab's own stack
    /// instead of hijacking Posts.
    @Test
    func resolvesPlainNavFromLiveSelectedTab() {
        let posts = UISplitViewController(style: .doubleColumn)
        let postsTab = UITab(
            title: "Posts",
            image: nil,
            identifier: MainWindowTabIdentifier.posts
        ) { _ in posts }
        let communitiesNav = UINavigationController(rootViewController: UIViewController())
        let communitiesTab = UITab(
            title: "Communities",
            image: nil,
            identifier: MainWindowTabIdentifier.communities
        ) { _ in communitiesNav }

        let tabBarController = UITabBarController()
        tabBarController.setTabs([postsTab, communitiesTab], animated: false)
        tabBarController.selectedTab = communitiesTab

        let target = SplitTabResolver.target(
            for: tabBarController.selectedTab?.viewController,
            postsSplit: posts
        )
        guard case let .plainNav(resolved) = target else {
            Issue.record("expected .plainNav, got \(target)")
            return
        }
        #expect(resolved === communitiesNav)
    }

    /// Regression test for CRITICAL 2: the Posts-tab QuickSwitch "Browse all
    /// communities" row used to write `tabBarController?.selectedIndex = 1`.
    /// Builds a real tab bar controller (Posts + Communities, addressed by
    /// `MainWindowTabIdentifier`) hosting the real
    /// `MainWindowSplitViewController`, starts on the Posts tab, invokes the
    /// same closure the row's tap wires to
    /// (`feedSwitcherViewController.onBrowseAllCommunities`), and asserts the
    /// Communities tab actually becomes selected.
    ///
    /// What this test DOES guarantee: the production closure is wired up and
    /// end-to-end selects Communities through a real `setTabs`-built
    /// controller. What it does NOT guarantee, despite the temptation to
    /// claim it: that a revert to `selectedIndex = 1` would be caught.
    /// Communities sits at array index 1 in both this fixture and production,
    /// so the old code would pass this test too. The discrimination lives in
    /// `indexBasedSelectionBreaksUnderReorderingButIdentifierBasedDoesNot`
    /// below, which reorders the tabs so index and identity disagree. (See
    /// the type doc comment above for why the old code isn't safe to rely on
    /// even though it isn't reproducibly broken on the current SDK.)
    @Test
    func browseAllCommunitiesSelectsCommunitiesTabByIdentifier() throws {
        let dependencies = FakeDependencies()
        let instance = try #require(InstanceActorId(from: "https://example.com"))
        let keychainId = dependencies.accountService.accountForSignedOut(
            forInstance: instance,
            isServiceAccount: false
        )

        let splitViewController = MainWindowSplitViewController(
            accountKeychainId: keychainId,
            isSignedIn: false,
            dependencies: dependencies
        )
        let communitiesNav = UINavigationController(rootViewController: UIViewController())

        let postsTab = UITab(
            title: "Posts",
            image: nil,
            identifier: MainWindowTabIdentifier.posts
        ) { _ in splitViewController }
        let communitiesTab = UITab(
            title: "Communities",
            image: nil,
            identifier: MainWindowTabIdentifier.communities
        ) { _ in communitiesNav }

        let tabBarController = UITabBarController()
        tabBarController.setTabs([postsTab, communitiesTab], animated: false)
        tabBarController.selectedTab = postsTab

        // Force the view hierarchy to resolve so `splitViewController`'s
        // `UIViewController.tabBarController` ancestor lookup — what the
        // production closure under test relies on — is actually populated.
        tabBarController.loadViewIfNeeded()
        try #require(splitViewController.tabBarController === tabBarController)

        splitViewController.feedSwitcherViewController.onBrowseAllCommunities?()

        #expect(tabBarController.selectedTab?.identifier == MainWindowTabIdentifier.communities)
    }

    /// Genuine red/green proof for why CRITICAL 2 was fixed to select by
    /// identifier instead of the literal previously-shipped
    /// `tabBarController?.selectedIndex = 1`: a direct empirical check (see
    /// the type doc comment) found that hardcoded index against `MainWindow`'s
    /// CURRENT tab order (Communities happens to sit at array index 1) does
    /// not reproduce a failure on this SDK, so
    /// `browseAllCommunitiesSelectsCommunitiesTabByIdentifier` above passes
    /// whether or not the fix is applied — it cannot, by itself, prove the
    /// fix matters. This test isolates the actual defect class: hardcoding a
    /// position instead of an identity. With Communities moved to index 2
    /// (a new tab inserted ahead of it, e.g. a future tab-order change),
    /// `selectedIndex = 1` silently lands on the WRONG tab while
    /// `tab(forIdentifier:)` keeps finding Communities regardless of where it
    /// sits in the array — demonstrating red (index) then green (identifier)
    /// within one test, without needing to revert any production code.
    @Test
    func indexBasedSelectionBreaksUnderReorderingButIdentifierBasedDoesNot() {
        let postsTab = UITab(
            title: "Posts",
            image: nil,
            identifier: MainWindowTabIdentifier.posts
        ) { _ in UIViewController() }
        let insertedTab = UITab(
            title: "Inserted",
            image: nil,
            identifier: "inserted"
        ) { _ in UIViewController() }
        let communitiesTab = UITab(
            title: "Communities",
            image: nil,
            identifier: MainWindowTabIdentifier.communities
        ) { _ in UIViewController() }

        let tabBarController = UITabBarController()
        // Communities is now at array index 2, not 1.
        tabBarController.setTabs([postsTab, insertedTab, communitiesTab], animated: false)
        tabBarController.selectedTab = postsTab

        // RED: the literal old code, hardcoding index 1.
        tabBarController.selectedIndex = 1
        #expect(
            tabBarController.selectedTab?.identifier != MainWindowTabIdentifier.communities,
            "hardcoded index 1 should have landed on the inserted tab, not Communities"
        )

        // GREEN: the fixed code, addressing by identifier — order-independent.
        tabBarController.selectedTab = postsTab
        if let tab = tabBarController.tab(forIdentifier: MainWindowTabIdentifier.communities) {
            tabBarController.selectedTab = tab
        }
        #expect(tabBarController.selectedTab?.identifier == MainWindowTabIdentifier.communities)
    }
}
