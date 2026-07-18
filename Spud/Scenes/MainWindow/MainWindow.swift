//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

class MainWindow: UIWindow {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase &
        HasDiagnosticLog &
        HasPreferencesService &
        HasUnreadCountService
    typealias NestedDependencies =
        AccountViewController.Dependencies &
        InboxViewController.Dependencies &
        MainWindowSplitViewController.Dependencies &
        OnboardingHomeBaseViewController.Dependencies &
        OutboundContentListViewController.Dependencies &
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

    private var diagnosticLog: DiagnosticLogging {
        dependencies.own.diagnosticLog
    }

    // MARK: Private

    /// Index of the Communities tab (subscriptions / Explore). Tab order:
    /// Posts 0 | Communities 1 | Search 2 | Inbox 3 | Account 4.
    private static let communitiesTabIndex = 1

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
    /// Observes whether ANY real account currently needs re-login and drives the
    /// Account tab's "!" badge.
    private var reauthBadgeObservationTask: Task<Void, Never>?
    private var appThemeObservationTask: Task<Void, Never>?
    private var accentColorObservationTask: Task<Void, Never>?
    /// Observes the active account's permanent outbox failures (a vote/save/hide
    /// rolled back after exhausting retries) and surfaces each as a toast.
    private var outboxFailureToastTask: Task<Void, Never>?
    /// Observes the active account's permanent composer failures (a post/comment
    /// that could not be submitted after exhausting retries) and surfaces each
    /// as an interactive toast offering a "View" action to open Drafts & Outbox.
    private var composerFailureToastTask: Task<Void, Never>?
    /// Keychain id of the account currently driving the tab bar — guards
    /// against rebuilds when the GRDB observation re-emits the same row.
    private var currentDefaultAccountKeychainId: String?

    /// The onboarding navigation controller while it is the window's root; nil
    /// once an account exists and the tab bar is installed.
    private var onboardingNavigationController: UINavigationController?

    // MARK: Functions

    init(
        windowScene: UIWindowScene,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)

        tabBarController = MainWindowTabBarController()

        super.init(windowScene: windowScene)

        seedDefaultAccountForUITestsIfRequested()
        #if DEBUG
        // Mutually exclusive with the signed-out seed above via the shared
        // `currentDefaultAccountKeychainId() == nil` guard: if both launch
        // arguments are passed, the signed-out seed runs first and wins.
        seedSignedInDefaultAccountForUITestsIfRequested()
        #endif

        // Durable launch event: fires once per cold start and records the instance
        // if an account is already present (fresh installs emit nil).
        let launchInstance = accountService.currentDefaultAccountKeychainId()
            .flatMap { accountService.instanceActorId(forAccountKeychainId: $0)?.hostWithPort }
        let diagnosticLog = dependencies.diagnosticLog
        Task {
            await diagnosticLog.record(
                category: .lifecycle,
                level: .info,
                event: "lifecycle.launch",
                message: "App launched",
                instance: launchInstance,
                metadata: nil
            )
        }

        // Gate on account presence: an existing account builds the tab bar; a
        // fresh install (no account) gets the onboarding flow as the root, and
        // the default-account observation swaps in the tab bar once the flow
        // creates the first account.
        if let keychainId = accountService.currentDefaultAccountKeychainId() {
            applyDefaultAccount(
                keychainId: keychainId,
                isSignedIn: !accountService.isSignedOut(forAccountKeychainId: keychainId),
                defaultPostSortType: accountService.defaultSortType(forAccountKeychainId: keychainId)
            )
            rootViewController = tabBarController
        } else {
            showOnboarding()
        }

        #if DEBUG
        seedNonLemmyLoginForUITestsIfRequested()
        #endif

        // Apply the persisted theme + accent synchronously before the window
        // is shown so there's no flash of the wrong appearance, then keep them
        // live via the preference streams.
        applyTheme(preferencesService.appTheme)
        applyAccent(preferencesService.accentColor)

        startObservingDefaultAccount()
        startObservingUnreadCount()
        startObservingReauthBadge()
        startObservingAppTheme()
        startObservingAccentColor()
    }

    deinit {
        defaultAccountObservationTask?.cancel()
        unreadCountObservationTask?.cancel()
        reauthBadgeObservationTask?.cancel()
        appThemeObservationTask?.cancel()
        accentColorObservationTask?.cancel()
        outboxFailureToastTask?.cancel()
        composerFailureToastTask?.cancel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)
        // Fun stats: count completed touches (taps, drag lifts) device-wide.
        // One increment per touch that ended this event; no-op when the
        // FunStats facade is not installed (tests) or collection is off.
        guard event.type == .touches, let touches = event.allTouches else { return }
        let ended = touches.filter { $0.phase == .ended }.count
        if ended > 0 {
            FunStats.record(.tapCount, amount: Double(ended))
        }
    }

    /// UI tests stub the feed for discuss.tchncs.de and expect to land on it at
    /// launch. The production auto-bootstrap that used to create that account is
    /// gone (onboarding now gates a fresh install), so a launch argument
    /// recreates the precondition here — at scene-connection time, after the
    /// test tunnel's filesystem reset — without shipping it. No-op otherwise.
    private func seedDefaultAccountForUITestsIfRequested() {
        guard
            ProcessInfo.processInfo.arguments
            .contains(AppLaunchArgument.seedSignedOutDefaultAccount.rawValue),
            accountService.currentDefaultAccountKeychainId() == nil,
            let instance = InstanceActorId(from: "https://discuss.tchncs.de")
        else { return }
        accountService.signInAsSignedOut(atInstance: instance)
    }

    #if DEBUG
    /// UI tests stub the feed for discuss.tchncs.de and expect to land on it
    /// already signed in. Mirrors `seedDefaultAccountForUITestsIfRequested`
    /// but seeds a signed-in account (fixed keychain id, fake JWT) via the
    /// DEBUG-only `AccountServiceType.seedSignedInDefaultAccount` seam. No-op
    /// otherwise; never compiled into release builds.
    private func seedSignedInDefaultAccountForUITestsIfRequested() {
        guard
            ProcessInfo.processInfo.arguments
            .contains(AppLaunchArgument.seedSignedInDefaultAccount.rawValue),
            accountService.currentDefaultAccountKeychainId() == nil,
            let instance = InstanceActorId(from: "https://discuss.tchncs.de")
        else { return }
        accountService.seedSignedInDefaultAccount(atInstance: instance)
    }

    /// UI-test seam: presents the login form for a non-Lemmy host directly,
    /// with the NodeInfo cache pre-seeded so the platform-block fires on
    /// "Log in" tap without any network call. The host is read from the
    /// `SPUDNonLemmyLoginHost` environment variable (default `"mastodon.social"`).
    /// The seeded software is Mastodon -- genuinely non-Lemmy, so login is
    /// blocked (unlike PieFed, whose Lemmy-compatible dialect Spud CAN log in
    /// to). Replaces whatever root was set by the onboarding branch in `init`
    /// (this method runs after `showOnboarding()`). Never compiled into
    /// release builds.
    private func seedNonLemmyLoginForUITestsIfRequested() {
        guard
            ProcessInfo.processInfo.arguments
            .contains(AppLaunchArgument.seedNonLemmyLoginForUITests.rawValue),
            accountService.currentDefaultAccountKeychainId() == nil
        else { return }

        let host = ProcessInfo.processInfo.environment["SPUDNonLemmyLoginHost"] ?? "mastodon.social"

        // Pre-seed the NodeInfo cache so detect(host:) short-circuits with
        // PlatformUnsupportedError instead of hitting the network.
        try! appDatabase.seedNodeInfoCacheForUITests(
            host: host,
            softwareName: "mastodon",
            softwareVersion: nil
        )

        guard let instance = InstanceActorId(from: "https://\(host)") else { return }

        let row = SiteListRow.forTypedInstance(instance)
        let loginViewController = LoginViewController(row: row, dependencies: dependencies.nested)
        let navigationController = UINavigationController(rootViewController: loginViewController)
        rootViewController = navigationController
    }
    #endif

    private func showOnboarding() {
        let welcomeViewController = OnboardingWelcomeViewController()
        welcomeViewController.onGetStarted = { [weak self] in
            guard let self else { return }
            let homeBaseViewController = OnboardingHomeBaseViewController(dependencies: dependencies.nested)
            onboardingNavigationController?.pushViewController(homeBaseViewController, animated: true)
        }
        let navigationController = UINavigationController(rootViewController: welcomeViewController)
        onboardingNavigationController = navigationController
        rootViewController = navigationController
    }

    /// Cross-fade the window's root from onboarding to the (already-populated)
    /// tab bar once the first account exists.
    private func swapRootToTabBar() {
        UIView.transition(
            with: self,
            duration: 0.3,
            options: .transitionCrossDissolve,
            animations: { [weak self] in
                guard let self else { return }
                rootViewController = tabBarController
            },
            completion: { [weak self] _ in self?.onboardingNavigationController = nil }
        )
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
                if onboardingNavigationController != nil {
                    swapRootToTabBar()
                }
            }
        }
    }

    private func applyDefaultAccount(
        keychainId: String,
        isSignedIn: Bool,
        defaultPostSortType: Lemmy.SortType
    ) {
        currentDefaultAccountKeychainId = keychainId

        let instance = accountService.instanceActorId(forAccountKeychainId: keychainId)?.hostWithPort
        let log = diagnosticLog
        Task {
            await log.record(
                category: .lifecycle,
                level: .info,
                event: "lifecycle.accountApplied",
                message: "Default account applied",
                instance: instance,
                metadata: nil
            )
        }

        // Keep the Spotlight community index current for this account.
        CommunitySpotlightIndexer.reindex(appDatabase: appDatabase, diagnostics: log)
        // Keep the Spotlight saved + history content index current too.
        ContentSpotlightIndexer.reindex(appDatabase: appDatabase, diagnostics: log)

        // Catch any time reminders that fired while we weren't running to
        // receive the OS notification callback - flips them fired/unseen so
        // the Inbox "Reminders" segment/badge is current on launch. Best-effort
        // (mirrors the Spotlight reindex calls above): a failed reconcile just
        // means the badge stays stale until the next launch/foreground.
        let reminderService = accountService.scope(forAccountKeychainId: keychainId).reminderService
        Task { try? await reminderService.reconcileOverdue(asOf: Date()) }

        // Surface this account's permanent outbox failures as toasts, and drain
        // any ops left pending from a previous session.
        startObservingOutboxFailures(keychainId: keychainId)
        startObservingComposerFailures(keychainId: keychainId)

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
        communitiesNavigationController.enableForwardNavigationGesture()

        // Tab: Setup the search view controller
        let searchViewController = SearchViewController(
            accountKeychainId: keychainId,
            dependencies: dependencies.nested
        )
        let searchNavigationController = UINavigationController(rootViewController: searchViewController)
        searchNavigationController.navigationBar.prefersLargeTitles = true
        searchNavigationController.enableForwardNavigationGesture()

        // Tab: Setup the inbox view controller
        let inboxViewController = InboxViewController(
            accountKeychainId: keychainId,
            isSignedIn: isSignedIn,
            dependencies: dependencies.nested
        )
        let inboxNavigationController = UINavigationController(rootViewController: inboxViewController)
        inboxNavigationController.enableForwardNavigationGesture()

        // Tab: Setup the account view controller. Settings is reached from the
        // Account nav-bar gear now, so Preferences is no longer its own tab.
        let accountViewController = AccountViewController(dependencies: dependencies.nested)
        let accountNavigationController = UINavigationController(rootViewController: accountViewController)
        accountNavigationController.enableForwardNavigationGesture()

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

    /// Live "any real account needs re-login" observation driving the Account
    /// tab's "!" badge — mirrors `startObservingUnreadCount`, but is account-wide
    /// (not tied to the currently-active account) since a re-login hint on a
    /// backgrounded account should still surface.
    private func startObservingReauthBadge() {
        reauthBadgeObservationTask?.cancel()
        let appDatabase = appDatabase
        reauthBadgeObservationTask = Task { @MainActor [weak self] in
            for await needsReauth in appDatabase.observeAnyAccountNeedsReauth() {
                if Task.isCancelled { break }
                self?.applyReauthBadge(needsReauth)
            }
        }
    }

    private func applyReauthBadge(_ needsReauth: Bool) {
        guard
            let items = tabBarController.tabBar.items,
            items.indices.contains(Self.accountTabIndex)
        else { return }
        items[Self.accountTabIndex].badgeValue = needsReauth ? "!" : nil
    }

    /// Subscribes to the active account's permanent outbox failures and surfaces
    /// each as a toast. Building the failure stream lazily constructs and
    /// `start()`s the outbox (enabling reachability-driven retry); we also drain
    /// any ops persisted from a previous session so they retry on launch. A
    /// signed-out account never enqueues, so there's nothing to observe.
    private func startObservingOutboxFailures(keychainId: String) {
        outboxFailureToastTask?.cancel()
        let scope = accountService.scope(forAccountKeychainId: keychainId)
        guard !scope.isSignedOut else {
            outboxFailureToastTask = nil
            return
        }
        outboxFailureToastTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let events = await scope.outboxFailureEvents()
            await scope.drainPendingOutbox()
            for await failure in events {
                guard currentDefaultAccountKeychainId == keychainId else { break }
                presentOutboxFailureToast(failure)
            }
        }
    }

    private func presentOutboxFailureToast(_ failure: OutboxFailure) {
        // An expired/revoked session takes priority over the reason/kind switch
        // below: the vote/save/hide itself was rolled back either way, but what
        // the user needs to know is "log back in", not which specific action
        // failed.
        if failure.isAuthExpiry {
            let keychainId = currentDefaultAccountKeychainId
            ToastPresenter.shared.show(
                NSLocalizedString("Session expired", comment: "Toast when an action failed because the session expired"),
                actionTitle: NSLocalizedString("Re-login", comment: "Toast action to re-authenticate the account"),
                in: self
            ) { [weak self] in
                guard let self, let keychainId else { return }
                AccountReauthLauncher.present(
                    forAccountKeychainId: keychainId,
                    from: topmostPresenter(),
                    accountService: accountService,
                    dependencies: dependencies.nested
                )
            }
            return
        }

        let message: String
        if failure.reason == .notFound {
            message = NSLocalizedString(
                "This post is no longer available",
                comment: "Toast when an action failed because the post was removed/deleted on the server"
            )
        } else {
            switch failure.kind {
            case .vote:
                message = NSLocalizedString("Couldn't vote", comment: "Toast when a vote permanently failed and was reverted")
            case .save:
                message = NSLocalizedString("Couldn't save", comment: "Toast when a save permanently failed and was reverted")
            case .hide:
                message = NSLocalizedString("Couldn't hide", comment: "Toast when a hide permanently failed and was reverted")
            case .delete:
                message = NSLocalizedString("Couldn't update comment", comment: "Toast when a comment delete/restore permanently failed and was reverted")
            case .subscribe:
                message = NSLocalizedString("Couldn't update subscription", comment: "Toast when a community subscribe/unsubscribe permanently failed and was reverted")
            }
        }
        ToastPresenter.shared.show(message, in: self)
    }

    /// The view controller currently on top of the visible hierarchy, for
    /// presenting a one-off modal (the re-auth login sheet) without stacking
    /// behind an already-presented screen. Starts from the selected tab's root
    /// (the same "current tab" notion `pushIntoCurrentContext` routes into) and
    /// walks any presented chain (e.g. the account switcher sheet) to its tip.
    private func topmostPresenter() -> UIViewController {
        var presenter: UIViewController = tabBarController.selectedViewController ?? tabBarController
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        return presenter
    }

    /// Subscribes to the active account's permanent composer failures (a
    /// post/comment rolled back after exhausting retries) and surfaces each as
    /// an interactive toast. A signed-out account never composes, so there is
    /// nothing to observe.
    private func startObservingComposerFailures(keychainId: String) {
        composerFailureToastTask?.cancel()
        let scope = accountService.scope(forAccountKeychainId: keychainId)
        guard !scope.isSignedOut else {
            composerFailureToastTask = nil
            return
        }
        composerFailureToastTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let events = await scope.composerFailureEvents()
            for await failure in events {
                guard currentDefaultAccountKeychainId == keychainId else { break }
                presentComposerFailureToast(failure, accountKeychainId: keychainId)
            }
        }
    }

    private func presentComposerFailureToast(_ failure: ComposerOutboxFailure, accountKeychainId: String) {
        let message = NSLocalizedString(
            "Couldn't post",
            comment: "Toast when a post or comment permanently failed to submit"
        )
        let actionTitle = NSLocalizedString(
            "View",
            comment: "Toast action button: open Drafts & Outbox to see the failed item"
        )
        ToastPresenter.shared.show(message, actionTitle: actionTitle, in: self) { [weak self] in
            self?.displayDraftsOutbox(accountKeychainId: accountKeychainId)
        }
    }

    /// Builds and pushes the Drafts & Outbox list for `accountKeychainId`
    /// into whichever tab is currently active.
    private func displayDraftsOutbox(accountKeychainId: String) {
        let vc = OutboundContentListViewController(
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        pushIntoCurrentContext(vc)
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

    /// Routes to the Communities tab (subscriptions / Explore) and resets it to
    /// root. Used by the Activity empty state's "Browse communities" escape hatch.
    func selectCommunitiesTab() {
        guard
            let viewControllers = tabBarController.viewControllers,
            viewControllers.indices.contains(Self.communitiesTabIndex)
        else { return }
        tabBarController.selectedIndex = Self.communitiesTabIndex
        (viewControllers[Self.communitiesTabIndex] as? UINavigationController)?
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
            navigationController.enableForwardNavigationGesture()
            splitViewController.showDetailViewController(navigationController, sender: self)
        }
    }

    func display(
        serverPostId: Lemmy.PostID,
        accountKeychainId: String,
        scrollToCommentId: Lemmy.CommentID? = nil
    ) {
        let postDetailVC = PostDetailOrEmptyViewController(
            serverPostId: serverPostId,
            accountKeychainId: accountKeychainId,
            scrollToCommentId: scrollToCommentId,
            dependencies: dependencies.nested
        )
        pushIntoCurrentContext(postDetailVC)
    }

    /// Pushes the optimistic pending-post screen for a just-queued post. When the
    /// outbox accepts the post the screen resolves to the real post detail,
    /// swapped in place so Back returns to wherever the user composed from.
    func displayPending(clientToken: String, accountKeychainId: String) {
        let pending = PendingPostViewController(
            clientToken: clientToken,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        pending.onResolvedPost = { [weak self, weak pending] serverPostId in
            guard let self, let pending else { return }
            let real = PostDetailOrEmptyViewController(
                serverPostId: serverPostId,
                accountKeychainId: accountKeychainId,
                dependencies: dependencies.nested
            )
            replaceTop(pending, with: real)
        }
        pending.onDiscarded = { [weak self, weak pending] in
            guard let pending else { return }
            self?.dismissPending(pending)
        }
        pushIntoCurrentContext(pending)
    }

    /// Replaces `viewController` with `replacement` in whichever navigation stack
    /// currently holds it, preserving everything beneath it. No-op if the user
    /// has already navigated away and `viewController` is no longer in a stack.
    private func replaceTop(_ viewController: UIViewController, with replacement: UIViewController) {
        guard
            let navigationController = viewController.navigationController,
            let index = navigationController.viewControllers.firstIndex(of: viewController)
        else { return }

        var stack = navigationController.viewControllers
        stack[index] = replacement
        navigationController.setViewControllers(stack, animated: false)
    }

    /// Dismisses a discarded pending-post screen in a context-aware way:
    /// - iPhone / pushed onto an existing stack: pop back to the previous VC.
    /// - iPad expanded split view: the pending VC is the single root of a fresh
    ///   secondary-column navigation controller — `popViewController` would be a
    ///   no-op and leave the user stranded on a dead screen. Replace it with the
    ///   empty post-detail placeholder so the detail column is usable again.
    private func dismissPending(_ vc: UIViewController) {
        guard let nav = vc.navigationController else { return }
        if nav.viewControllers.count > 1 {
            nav.popViewController(animated: true)
        } else {
            guard let keychainId = currentDefaultAccountKeychainId ?? accountService.currentDefaultAccountKeychainId() else {
                return
            }
            let emptyDetailViewController = PostDetailOrEmptyViewController(
                accountKeychainId: keychainId,
                dependencies: dependencies.nested
            )
            nav.setViewControllers([emptyDetailViewController], animated: false)
        }
    }

    func display(communityName: String, instance: InstanceActorId, accountKeychainId: String) {
        let vc = CommunityOrLoadingViewController(
            communityName: communityName,
            instance: instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        pushIntoCurrentContext(vc)
    }

    func display(personId: Lemmy.PersonID, instance: InstanceActorId, accountKeychainId: String) {
        let vc = PersonOrLoadingViewController(
            personId: personId,
            instance: instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        pushIntoCurrentContext(vc)
    }

    /// Pushes a screen into whichever tab the user is currently in, so Back
    /// returns to where they were (e.g. a community in the Communities tab)
    /// instead of hijacking the Posts tab.
    ///
    /// Each tab can host a different detail context, so the destination is
    /// resolved through `SplitTabResolver`:
    /// - The Posts tab is the real `UISplitViewController` — route via
    ///   `pushDetail` (collapsed-aware push vs. secondary-column replace).
    /// - A community reading split on top of another tab's nav stack (e.g.
    ///   Communities) — route detail into ITS secondary column via
    ///   `showDetail(_:)`, so the community feed stays visible beside it on iPad
    ///   instead of the post pushing full-screen or hijacking the Posts tab.
    /// - An Activity timeline + Summary split on top of a tab's nav stack (the
    ///   Account tab's Activity at regular width) — likewise route detail into ITS
    ///   secondary column via `showDetail(_:)`, over the pinned Summary.
    /// - Any other (single-column) tab — a normal push onto its nav stack.
    /// - No navigation context (e.g. a cold deep link) — fall back to the Posts
    ///   tab.
    private func pushIntoCurrentContext(_ viewController: UIViewController) {
        let selected = tabBarController.selectedViewController
        guard let splitViewController else {
            // No Posts split yet — the only sensible push target is the selected
            // tab's nav stack, if there is one.
            (selected as? UINavigationController)?.pushViewController(viewController, animated: true)
            return
        }

        switch SplitTabResolver.target(for: selected, postsSplit: splitViewController) {
        case .postsSplit:
            pushDetail(viewController: viewController)
        case let .community(community):
            community.showDetail(viewController)
        case let .activitySummary(split):
            split.showDetail(viewController)
        case let .plainNav(navigationController):
            navigationController.pushViewController(viewController, animated: true)
        case .none:
            tabBarController.selectedIndex = 0
            pushDetail(viewController: viewController)
        }
    }
}

// MARK: - AppNavigating (App Intents / Siri navigation)

extension MainWindow: AppNavigating {
    // Tab order: Posts 0 | Communities 1 | Search 2 | Inbox 3 | Account 4.

    func selectFeed(listing: Lemmy.ListingType, sort: Lemmy.SortType?) {
        tabBarController.selectedIndex = 0
        let postListVC = splitViewController?.postListViewController
        postListVC?.showFeed(.frontpage(
            listingType: adjustedListing(listing),
            sortType: sort ?? .Hot
        ))
    }

    func selectSavedFeed(sort: Lemmy.SortType?) {
        tabBarController.selectedIndex = 0
        let postListVC = splitViewController?.postListViewController
        postListVC?.showFeed(.saved(sortType: sort ?? .Hot))
    }

    func selectSearch(query: String) {
        tabBarController.selectedIndex = 2
        guard
            let viewControllers = tabBarController.viewControllers,
            viewControllers.indices.contains(2),
            let navigationController = viewControllers[2] as? UINavigationController,
            let searchViewController = navigationController.viewControllers.first as? SearchViewController
        else { return }
        searchViewController.setSearchQuery(query)
    }

    func presentNewPost() {
        tabBarController.selectedIndex = 0
        let postListVC = splitViewController?.postListViewController
        postListVC?.beginNewPost()
    }

    func selectInbox() {
        tabBarController.selectedIndex = 3
    }

    // `display(communityName:instance:accountKeychainId:)` already satisfies the
    // protocol requirement.

    /// Subscribed / Moderator feeds are meaningless when signed out; fall back to
    /// All, mirroring the widget's signed-out behavior.
    private func adjustedListing(
        _ listing: Lemmy.ListingType
    ) -> Lemmy.ListingType {
        let signedOut = accountService.currentDefaultAccountKeychainId()
            .map { accountService.isSignedOut(forAccountKeychainId: $0) } ?? true
        if signedOut, listing == .Subscribed || listing == .ModeratorView {
            return .All
        }
        return listing
    }
}

extension MainWindow: UISplitViewControllerDelegate {
    /// Collapsing from two columns (regular width) to one (compact width):
    /// e.g. rotating a Max-class iPhone back to portrait, or narrowing an iPad
    /// multitasking split. Two jobs:
    /// 1. Re-insert the feed switcher beneath the post list (its compact home),
    ///    so the system left-edge back gesture reveals it again — it was stripped
    ///    from the base while expanded (regular width uses a navbar-title popover).
    /// 2. Carry whatever post detail was visible in the secondary column onto the
    ///    (now single) compact navigation stack so it stays on screen instead of
    ///    vanishing.
    func splitViewControllerDidCollapse(_ svc: UISplitViewController) {
        guard let splitViewController else { return }
        let primaryNav = splitViewController.postListNavigationController

        // 1. Re-insert the feed switcher at the base (index 0) if it was stripped
        //    while expanded, so the compact back-swipe reveals it again.
        var primaryStack = primaryNav.viewControllers
        if
            let feedSwitcher = splitViewController.feedSwitcherViewController,
            !primaryStack.contains(feedSwitcher)
        {
            primaryStack.insert(feedSwitcher, at: 0)
        }

        // 2. Carry any real detail content (skip the empty placeholder) from the
        //    secondary column onto the now-single compact stack.
        if let secondaryNav = svc.viewController(for: .secondary) as? UINavigationController {
            let detailViewControllers = secondaryNav.viewControllers.filter { viewController in
                if let orEmpty = viewController as? PostDetailOrEmptyViewController {
                    return !orEmpty.isEmptyPlaceholder
                }
                return true
            }
            if !detailViewControllers.isEmpty {
                secondaryNav.setViewControllers([], animated: false)
                primaryStack += detailViewControllers
            }
        }

        primaryNav.setViewControllers(primaryStack, animated: false)
    }

    /// Expanding from one column (compact width) to two (regular width): the
    /// reverse handoff. Two jobs:
    /// 1. Strip the feed switcher from the base — in regular width the persistent
    ///    primary column must never pop to it (feed selection is a navbar-title
    ///    popover instead).
    /// 2. Pull the detail content that was pushed onto the compact stack back out
    ///    into the secondary column, leaving the primary column showing just the
    ///    post list.
    func splitViewControllerDidExpand(_ svc: UISplitViewController) {
        guard let splitViewController else { return }
        let primaryNav = splitViewController.postListNavigationController

        // 1. Remove the feed switcher wherever it sits in the stack.
        var stack = primaryNav.viewControllers
        if let feedSwitcher = splitViewController.feedSwitcherViewController {
            stack.removeAll { $0 === feedSwitcher }
        }

        // 2. With the switcher gone the regular-width base is the post list alone
        //    (index 0); anything above it is detail to hand back to the secondary
        //    column.
        let baseDepth = 1
        guard stack.count > baseDepth else {
            // Nothing was drilled into; commit the switcher-stripped base and
            // ensure the secondary shows the empty state.
            primaryNav.setViewControllers(stack, animated: false)
            restoreEmptySecondaryColumn(in: svc)
            return
        }

        let baseViewControllers = Array(stack.prefix(baseDepth))
        let detailViewControllers = Array(stack.suffix(from: baseDepth))

        primaryNav.setViewControllers(baseViewControllers, animated: false)

        let detailNav = UINavigationController()
        detailNav.setViewControllers(detailViewControllers, animated: false)
        detailNav.enableForwardNavigationGesture()
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

        guard let keychainId = currentDefaultAccountKeychainId ?? accountService.currentDefaultAccountKeychainId() else {
            return
        }
        let emptyDetailViewController = PostDetailOrEmptyViewController(
            accountKeychainId: keychainId,
            dependencies: dependencies.nested
        )
        let detailNav = UINavigationController(rootViewController: emptyDetailViewController)
        detailNav.enableForwardNavigationGesture()
        svc.setViewController(detailNav, for: .secondary)
    }
}
