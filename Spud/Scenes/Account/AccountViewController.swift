//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import SwiftUI
import UIKit

/// The Account tab. When signed in it shows `AccountView`: a tappable profile
/// header (-> Edit Profile) over a grouped list of account actions (Switch
/// account, Saved, Activity, Your posts, Your comments, Log out), with Settings
/// in the nav bar. When signed out it shows a clean call-to-action to Log in or
/// Sign up, with anonymous browsing remaining the default.
class AccountViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasImageService
    /// Spelled out as a concrete composition (rather than the child VCs'
    /// `Dependencies` typealiases) to avoid recursive typealias cycles through
    /// the scene graph. This is the union those expand to; the live
    /// `DependencyContainer` conforms to all of them.
    typealias NestedDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasAppService &
        HasAppearanceService &
        HasDiagnosticLog &
        HasExplorerService &
        HasImageService &
        HasLinkEmbedService &
        HasPostContentDetectorService &
        HasPreferencesService &
        HasReachabilityMonitor &
        HasSiteService &
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    // MARK: Private

    private let viewModel: AccountViewModel

    private var observationTask: Task<Void, Never>?

    /// The keychain id the current layout was built for, so the screen only
    /// rebuilds when the account or its sign-in state actually changes.
    private var renderedKeychainId: String?
    private var renderedSignedIn: Bool?
    private var renderedHasOwnPerson: Bool?
    /// Tracked so a home-host change refreshes the signed-out "Reading from" row.
    private var renderedInstanceHostname: String?

    private var currentChild: UIViewController?

    // MARK: Functions

    init(dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        viewModel = AccountViewModel(
            accountService: dependencies.accountService,
            appDatabase: dependencies.appDatabase
        )

        super.init(nibName: nil, bundle: nil)

        tabBarItem.title = NSLocalizedString("Account", comment: "Account tab title")
        tabBarItem.image = UIImage(systemName: "person.crop.circle")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observationTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        startObservation()
    }

    private func startObservation() {
        observationTask?.cancel()
        let viewModel = viewModel
        observationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: {
                // instanceHostname is observed too so the signed-out "Reading from"
                // row refreshes if the home host changes without the keychainId.
                (viewModel.isSignedIn, viewModel.accountKeychainId, viewModel.ownPerson, viewModel.instanceHostname)
            }) {
                if Task.isCancelled { break }
                self?.renderIfNeeded()
            }
        }
    }

    private func renderIfNeeded() {
        let keychainId = viewModel.accountKeychainId
        guard !keychainId.isEmpty else { return }

        let signedIn = viewModel.isSignedIn
        let hasOwnPerson = viewModel.ownPerson != nil
        let instanceHostname = viewModel.instanceHostname

        // Rebuild only on a meaningful change. When signed in but the person
        // row hasn't been imported yet, rebuild once it appears so the embedded
        // profile can resolve. The host is tracked so the signed-out "Reading
        // from" row refreshes if the home server changes.
        guard
            keychainId != renderedKeychainId ||
            signedIn != renderedSignedIn ||
            hasOwnPerson != renderedHasOwnPerson ||
            instanceHostname != renderedInstanceHostname
        else { return }

        renderedKeychainId = keychainId
        renderedSignedIn = signedIn
        renderedHasOwnPerson = hasOwnPerson
        renderedInstanceHostname = instanceHostname

        if signedIn {
            showSignedIn(keychainId: keychainId)
        } else {
            showSignedOut(keychainId: keychainId)
        }
    }

    // MARK: Layouts

    private func showSignedIn(keychainId: String) {
        configureNavBar(signedIn: true)

        guard viewModel.ownPerson != nil else {
            // Signed in but the person row hasn't landed yet (first login). Show
            // a spinner; the observation rebuilds when the import completes.
            showLoading()
            return
        }

        // A clean SwiftUI list: a tappable profile header over the account
        // actions (switch account, saved / your posts / your comments, log out).
        // Navigation is owned here so each row works on iPhone and iPad.
        let accent = Color(ThemeManager.currentAccentColor)
        let accountView = AccountView(
            viewModel: viewModel,
            accent: accent,
            onEditProfile: { [weak self] in self?.openEditProfile(keychainId: keychainId) },
            onSwitchAccount: { [weak self] in self?.accountsTapped() },
            onOpenSaved: { [weak self] in self?.openActivity(keychainId: keychainId, initialFilters: [.save]) },
            onOpenActivity: { [weak self] in self?.openActivity(keychainId: keychainId) },
            onOpenYourPosts: { [weak self] in self?.openActivity(keychainId: keychainId, initialFilters: [.post]) },
            onOpenYourComments: { [weak self] in self?.openActivity(keychainId: keychainId, initialFilters: [.comment]) },
            onLogout: { [weak self] in self?.confirmLogout() }
        )
        .environment(\.imageService, imageService)

        let hostingVC = UIHostingController(rootView: accountView)
        swapChild(hostingVC)
    }

    private func showSignedOut(keychainId _: String) {
        configureNavBar(signedIn: false)

        // A grouped SwiftUI screen mirroring the signed-in Account tab: a guest
        // header, a "Reading from <host>" row to change the home server, the
        // Create account / Log in buttons, and a Settings row. Navigation is owned
        // here so each control works on iPhone and iPad.
        let accent = Color(ThemeManager.currentAccentColor)
        let signedOutVC = AccountSignedOutViewController(
            instanceHostname: viewModel.instanceHostname,
            accent: accent,
            onChangeInstance: { [weak self] in self?.accountsTapped() },
            onCreateAccount: { [weak self] in self?.openLoginFlow() },
            onLogIn: { [weak self] in self?.openLoginFlow() },
            onSettings: { [weak self] in self?.settingsTapped() }
        )
        swapChild(signedOutVC)
    }

    private func showLoading() {
        let loadingVC = UIViewController()
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        loadingVC.view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: loadingVC.view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: loadingVC.view.centerYAnchor),
        ])
        swapChild(loadingVC)
    }

    private func swapChild(_ newChild: UIViewController) {
        removeCurrentChild()
        currentChild = newChild
        add(child: newChild)
        addSubviewWithEdgeConstraints(child: newChild)
        newChild.didMove(toParent: self)
    }

    private func removeCurrentChild() {
        currentChild?.view.removeFromSuperview()
        remove(child: currentChild)
        currentChild = nil
    }

    // MARK: Nav bar

    private func configureNavBar(signedIn: Bool) {
        navigationItem.title = NSLocalizedString("Account", comment: "Account screen title")

        if signedIn {
            // Signed in, "Switch account" folds into the list (per the redesign),
            // so the nav bar carries only Settings.
            let settingsButton = UIBarButtonItem(
                image: UIImage(systemName: "gearshape"),
                style: .plain,
                target: self,
                action: #selector(settingsTapped)
            )
            settingsButton.accessibilityLabel = NSLocalizedString("Settings", comment: "Settings button accessibility label")
            navigationItem.rightBarButtonItems = [settingsButton]
        } else {
            // Signed out, the redesigned in-content rows cover everything the nav
            // bar used to: the "Reading from" / Change row replaces the switcher,
            // the Settings row replaces the gear, and Create account / Log in
            // replace the call-to-action. So the nav bar is just the title.
            navigationItem.rightBarButtonItems = nil
        }
    }

    // MARK: Actions

    /// Presents the account switcher as a bottom sheet. The switcher
    /// (`AccountListViewController` hosting `AccountSwitcherView`) configures its
    /// own detents and grabber and carries its own "Accounts" title, so it is
    /// presented directly — no `UINavigationController` wrapper.
    @objc
    private func accountsTapped() {
        Haptics.tap()
        let accountListViewController = AccountListViewController(
            dependencies: dependencies.nested
        )
        present(accountListViewController, animated: true)
    }

    @objc
    private func settingsTapped() {
        Haptics.tap()
        let keychainId = viewModel.accountKeychainId
        guard !keychainId.isEmpty else { return }
        let sortType = accountService.defaultSortType(forAccountKeychainId: keychainId)
        let preferencesViewController = PreferencesViewController(
            defaultPostSortType: sortType,
            accountKeychainId: keychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(preferencesViewController, animated: true)
    }

    /// Presents the Edit Profile editor for the signed-in account, reached by
    /// tapping the profile header.
    private func openEditProfile(keychainId: String) {
        Haptics.tap()
        let editor = EditProfileViewController.makeModal(
            accountKeychainId: keychainId,
            dependencies: dependencies.own
        )
        present(editor, animated: true)
    }

    /// Pushes the Activity screen pre-filtered to `initialFilters`.
    ///
    /// All four Account tab action rows (Saved, Activity, Your posts, Your comments)
    /// funnel here; each supplies a different preset so the screen opens in the
    /// relevant view while the user can still toggle other filters freely.
    private func openActivity(keychainId: String, initialFilters: Set<ActivityFilterType> = []) {
        Haptics.tap()
        let activityVC = ActivityViewController(
            accountKeychainId: keychainId,
            initialFilters: initialFilters,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(activityVC, animated: true)
    }

    private func confirmLogout() {
        Haptics.warning()
        let alert = UIAlertController(
            title: NSLocalizedString("Log out?", comment: "Logout confirmation title"),
            message: NSLocalizedString(
                "You'll go back to browsing anonymously. You can log in again any time.",
                comment: "Logout confirmation message"
            ),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Log out", comment: "Logout confirm button"),
            style: .destructive
        ) { [weak self] _ in
            Haptics.success()
            self?.viewModel.logout()
        })
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: "Cancel button"),
            style: .cancel
        ))
        alert.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(alert, animated: true)
    }

    /// Opens the add-account flow (site picker -> login / sign up), the same
    /// path the account switcher's "+" uses.
    private func openLoginFlow() {
        Haptics.tap()
        let siteListViewController = SiteListViewController(
            dependencies: dependencies.nested
        )
        let navigationController = UINavigationController(rootViewController: siteListViewController)
        present(navigationController, animated: true)
    }
}
