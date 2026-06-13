//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import SpudUIKit
import UIKit

class MainWindow: UIWindow {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase &
        HasPreferencesService &
        HasUnreadCountService
    typealias NestedDependencies =
        AccountViewController.Dependencies &
        InboxViewController.Dependencies &
        MainWindowSplitViewController.Dependencies &
        PreferencesViewController.Dependencies &
        SearchViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    private var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    private var unreadCountService: UnreadCountServiceType {
        dependencies.own.unreadCountService
    }

    private var preferencesService: PreferencesServiceType {
        dependencies.own.preferencesService
    }

    // MARK: Private

    /// Index of the Inbox tab in the tab bar; its `badgeValue` reflects the
    /// observable unread count.
    private static let inboxTabIndex = 3

    /// Index of the Account tab; the sign-in gate routes here (it offers log-in
    /// and sign-up) when a signed-out user chooses to authenticate.
    private static let accountTabIndex = 4

    private let tabBarController: MainWindowTabBarController
    private var splitViewController: MainWindowSplitViewController?
    private var defaultAccountObservationTask: Task<Void, Never>?
    private var unreadCountObservationTask: Task<Void, Never>?
    private var appThemeObservationTask: Task<Void, Never>?
    private var accentColorObservationTask: Task<Void, Never>?
    /// Keychain id of the account currently driving the tab bar — guards
    /// against rebuilds when the GRDB observation re-emits the same row.
    private var currentDefaultAccountKeychainId: String?

    // MARK: Functions

    init(
        windowScene: UIWindowScene,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)

        tabBarController = MainWindowTabBarController()

        super.init(windowScene: windowScene)

        // Bootstrap synchronously: defaultAccountKeychainId() ensures one
        // exists and is marked default, which the GRDB observation will
        // subsequently mirror. The follow-up reads pull whatever we need
        // straight from AppDatabase.
        let keychainId = accountService.defaultAccountKeychainId()
        applyDefaultAccount(
            keychainId: keychainId,
            isSignedIn: !accountService.isSignedOut(forAccountKeychainId: keychainId),
            defaultPostSortType: accountService.defaultSortType(forAccountKeychainId: keychainId)
        )

        rootViewController = tabBarController

        // Apply the persisted theme + accent synchronously before the window
        // is shown so there's no flash of the wrong appearance, then keep them
        // live via the preference streams.
        applyTheme(preferencesService.appTheme)
        applyAccent(preferencesService.accentColor)

        startObservingDefaultAccount()
        startObservingUnreadCount()
        startObservingAppTheme()
        startObservingAccentColor()
    }

    deinit {
        defaultAccountObservationTask?.cancel()
        unreadCountObservationTask?.cancel()
        appThemeObservationTask?.cancel()
        accentColorObservationTask?.cancel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func startObservingDefaultAccount() {
        defaultAccountObservationTask?.cancel()
        defaultAccountObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await record in appDatabase.observeDefaultAccount() {
                if Task.isCancelled { break }
                guard let record else { continue }
                guard record.accountKeychainId != currentDefaultAccountKeychainId else { continue }
                applyDefaultAccount(
                    keychainId: record.accountKeychainId,
                    isSignedIn: !record.isSignedOutAccountType,
                    defaultPostSortType: record.resolvedDefaultSortType
                )
            }
        }
    }

    private func applyDefaultAccount(
        keychainId: String,
        isSignedIn: Bool,
        defaultPostSortType: Components.Schemas.SortType
    ) {
        currentDefaultAccountKeychainId = keychainId

        // Tab: Setup the split view controller
        let splitViewController = MainWindowSplitViewController(
            accountKeychainId: keychainId,
            isSignedIn: isSignedIn,
            dependencies: dependencies.nested
        )
        self.splitViewController = splitViewController
        splitViewController.delegate = self

        // Tab: Communities — the subscriptions / management surface promoted to
        // a first-class tab (it was a split-view sidebar, unreachable on iPhone).
        let communitiesViewController = SubscriptionsViewController(
            accountKeychainId: keychainId,
            isSignedIn: isSignedIn,
            dependencies: dependencies.nested
        )
        communitiesViewController.navigationItem.title = NSLocalizedString("Communities", comment: "Communities tab title")
        let communitiesNavigationController = UINavigationController(rootViewController: communitiesViewController)
        communitiesNavigationController.navigationBar.prefersLargeTitles = true
        communitiesNavigationController.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Communities", comment: "Communities tab title"),
            image: UIImage(systemName: "person.3"),
            selectedImage: UIImage(systemName: "person.3.fill")
        )

        // Tab: Setup the search view controller
        let searchViewController = SearchViewController(
            accountKeychainId: keychainId,
            dependencies: dependencies.nested
        )
        let searchNavigationController = UINavigationController(rootViewController: searchViewController)
        searchNavigationController.navigationBar.prefersLargeTitles = true

        // Tab: Setup the inbox view controller
        let inboxViewController = InboxViewController(
            accountKeychainId: keychainId,
            isSignedIn: isSignedIn,
            dependencies: dependencies.nested
        )
        let inboxNavigationController = UINavigationController(rootViewController: inboxViewController)

        // Tab: Setup the account view controller. Settings is reached from the
        // Account nav-bar gear now, so Preferences is no longer its own tab.
        let accountViewController = AccountViewController(dependencies: dependencies.nested)
        let accountNavigationController = UINavigationController(rootViewController: accountViewController)

        // Tabs: Posts | Communities | Search | Inbox | Account. Inbox sits at
        // index 3 so its badge can be addressed via Self.inboxTabIndex.
        tabBarController.setViewControllers(
            [
                splitViewController,
                communitiesNavigationController,
                searchNavigationController,
                inboxNavigationController,
                accountNavigationController,
            ],
            animated: false
        )

        applyUnreadBadge(unreadCountService.unreadCount)

        // Pull the unread count for the newly-active account.
        let unreadCountService = unreadCountService
        Task { await unreadCountService.refresh(accountKeychainId: keychainId) }
    }

    private func startObservingUnreadCount() {
        unreadCountObservationTask?.cancel()
        let unreadCountService = unreadCountService
        unreadCountObservationTask = Task { @MainActor [weak self] in
            for await count in ObservationStream.values(of: { unreadCountService.unreadCount }) {
                if Task.isCancelled { break }
                self?.applyUnreadBadge(count)
            }
        }
    }

    private func applyUnreadBadge(_ count: UnreadCount) {
        guard
            let items = tabBarController.tabBar.items,
            items.indices.contains(Self.inboxTabIndex)
        else { return }
        items[Self.inboxTabIndex].badgeValue = count.total > 0 ? "\(count.total)" : nil
    }

    /// Routes to the Account tab (its signed-out screen offers log in / sign
    /// up) and resets it to root. Called from the sign-in gate.
    func selectAccountTab() {
        guard
            let viewControllers = tabBarController.viewControllers,
            viewControllers.indices.contains(Self.accountTabIndex)
        else { return }
        tabBarController.selectedIndex = Self.accountTabIndex
        (viewControllers[Self.accountTabIndex] as? UINavigationController)?
            .popToRootViewController(animated: false)
    }

    // MARK: Theming

    private func startObservingAppTheme() {
        appThemeObservationTask?.cancel()
        let preferencesService = preferencesService
        appThemeObservationTask = Task { @MainActor [weak self] in
            for await theme in preferencesService.appThemeStream {
                if Task.isCancelled { break }
                self?.applyTheme(theme)
            }
        }
    }

    private func startObservingAccentColor() {
        accentColorObservationTask?.cancel()
        let preferencesService = preferencesService
        accentColorObservationTask = Task { @MainActor [weak self] in
            for await accent in preferencesService.accentColorStream {
                if Task.isCancelled { break }
                self?.applyAccent(accent)
            }
        }
    }

    /// Applies the theme to this window. Sets the interface style (which
    /// drives a trait-collection change so the theme-aware `Theme` color
    /// providers re-resolve, swapping backgrounds to true black under OLED)
    /// and records it on the shared `ThemeManager` so those providers see the
    /// True-Black flag.
    ///
    /// Switching between standard Dark and True-Black keeps the same
    /// `overrideUserInterfaceStyle` (`.dark`), so UIKit fires no trait change
    /// and the dynamic `Theme` colors would not re-resolve. In that case we
    /// nudge the window through `.unspecified` and back on the next runloop
    /// tick to force a real trait change. Every other transition changes the
    /// style outright and refreshes instantly.
    private func applyTheme(_ theme: AppTheme) {
        let newStyle = theme.userInterfaceStyle
        let styleUnchanged = overrideUserInterfaceStyle == newStyle

        ThemeManager.shared.setTheme(theme)

        if styleUnchanged, newStyle == .dark {
            // Dark <-> True-Black: same style, force re-resolution.
            overrideUserInterfaceStyle = .unspecified
            Task { @MainActor [weak self] in
                self?.overrideUserInterfaceStyle = newStyle
            }
        } else {
            overrideUserInterfaceStyle = newStyle
        }
    }

    /// Applies the accent color: drives `tintColor` (which UIKit propagates to
    /// the view hierarchy, retinting buttons/links/controls) and records it on
    /// the shared `ThemeManager`.
    private func applyAccent(_ accent: AccentColor) {
        ThemeManager.shared.setAccent(accent)
        tintColor = accent.color
    }

    /// Refreshes the unread count for the active account. Called on app
    /// foreground (and could be driven by a background-refresh task later).
    func refreshUnreadCount() {
        guard let keychainId = currentDefaultAccountKeychainId else { return }
        let unreadCountService = unreadCountService
        Task { await unreadCountService.refresh(accountKeychainId: keychainId) }
    }

    /// Pushes the given view controller as a detail view.
    private func pushDetail(viewController: UIViewController) {
        guard let splitViewController else {
            fatalError()
        }

        if splitViewController.isCollapsed {
            let navigationController = splitViewController.postListNavigationController
            navigationController.pushViewController(viewController, animated: true)
        } else {
            // we make a new navigation controller here to make UISplitVC replace the
            // detail screen instead of pushing a new PostDetail VC onto the stack.
            let navigationController = UINavigationController(rootViewController: viewController)
            splitViewController.showDetailViewController(navigationController, sender: self)
        }
    }

    func display(serverPostId: Components.Schemas.PostID, accountKeychainId: String) {
        // Switch to the post content tab
        tabBarController.selectedIndex = 0

        let postDetailVC = PostDetailOrEmptyViewController(
            serverPostId: serverPostId,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )

        pushDetail(viewController: postDetailVC)
    }
}

extension MainWindow: UISplitViewControllerDelegate {
    /// The post list navigation stack's base depth: `[PostListViewController]`
    /// (the feed is the root of the Posts tab now). Anything pushed above this
    /// (a post detail and whatever the user drilled into from it) is "detail"
    /// content that belongs in the secondary column when the split view is
    /// expanded.
    private static let postListBaseStackDepth = 1

    /// Collapsing from two columns (regular width) to one (compact width):
    /// e.g. rotating a Max-class iPhone back to portrait, or narrowing an iPad
    /// multitasking split. Carry whatever post detail was visible in the
    /// secondary column onto the (now single) compact navigation stack so it
    /// stays on screen instead of vanishing.
    func splitViewControllerDidCollapse(_ svc: UISplitViewController) {
        guard let splitViewController else { return }
        let primaryNav = splitViewController.postListNavigationController

        guard
            let secondaryNav = svc.viewController(for: .secondary) as? UINavigationController
        else { return }

        // Skip the empty placeholder; carry over any real detail content.
        let detailViewControllers = secondaryNav.viewControllers.filter { viewController in
            if let orEmpty = viewController as? PostDetailOrEmptyViewController {
                return !orEmpty.isEmptyPlaceholder
            }
            return true
        }
        guard !detailViewControllers.isEmpty else { return }

        secondaryNav.setViewControllers([], animated: false)
        primaryNav.setViewControllers(
            primaryNav.viewControllers + detailViewControllers,
            animated: false
        )
    }

    /// Expanding from one column (compact width) to two (regular width): the
    /// reverse handoff. Pull the detail content that was pushed onto the compact
    /// navigation stack back out into the secondary column, leaving the primary
    /// column showing just the post list.
    func splitViewControllerDidExpand(_ svc: UISplitViewController) {
        guard let splitViewController else { return }
        let primaryNav = splitViewController.postListNavigationController

        let stack = primaryNav.viewControllers
        guard stack.count > Self.postListBaseStackDepth else {
            // Nothing was drilled into; ensure the secondary shows the empty state.
            restoreEmptySecondaryColumn(in: svc)
            return
        }

        let baseViewControllers = Array(stack.prefix(Self.postListBaseStackDepth))
        let detailViewControllers = Array(stack.suffix(from: Self.postListBaseStackDepth))

        primaryNav.setViewControllers(baseViewControllers, animated: false)

        let detailNav = UINavigationController()
        detailNav.setViewControllers(detailViewControllers, animated: false)
        svc.setViewController(detailNav, for: .secondary)
    }

    private func restoreEmptySecondaryColumn(in svc: UISplitViewController) {
        // Only install a fresh empty placeholder if the secondary column isn't
        // already showing post content (avoids clobbering a valid detail).
        if
            let secondaryNav = svc.viewController(for: .secondary) as? UINavigationController,
            secondaryNav.viewControllers.contains(where: { viewController in
                if let orEmpty = viewController as? PostDetailOrEmptyViewController {
                    return !orEmpty.isEmptyPlaceholder
                }
                return true
            })
        {
            return
        }

        let emptyDetailViewController = PostDetailOrEmptyViewController(
            accountKeychainId: currentDefaultAccountKeychainId ?? accountService.defaultAccountKeychainId(),
            dependencies: dependencies.nested
        )
        let detailNav = UINavigationController(rootViewController: emptyDetailViewController)
        svc.setViewController(detailNav, for: .secondary)
    }
}
