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

        // Tab: Setup the account view controller
        let accountViewController = AccountViewController(dependencies: dependencies.nested)
        let accountNavigationController = UINavigationController(rootViewController: accountViewController)

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

        // Tab: Setup the preferences view controller
        let preferencesViewController = PreferencesViewController(
            defaultPostSortType: defaultPostSortType,
            accountKeychainId: keychainId,
            dependencies: dependencies.nested
        )

        // Setup the tab bar controller. Inbox sits at index 3 so its badge can
        // be addressed via Self.inboxTabIndex.
        tabBarController.setViewControllers(
            [
                splitViewController,
                accountNavigationController,
                searchNavigationController,
                inboxNavigationController,
                preferencesViewController,
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
    func splitViewControllerDidCollapse(_ svc: UISplitViewController) {
        // TODO: move the navigation stack from Primary column to Compact column
        // when collapsing i.e. transitioning to compact state and back.
        //
        // This happens when e.g. on iPhone when start navigating - press on a post
        // in the PostList, we push to Primary column's NC; Then rotate the phone to landscape
        // and suddenly Detail VC is visible - but the Primary NC still has the navigation
        // stack that should instead be shown in the Secondary column.
    }
}
