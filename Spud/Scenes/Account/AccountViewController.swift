//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

private let logger = Logger.app

/// The Account tab. When signed in it shows the account holder's own Person
/// profile (header + their posts/comments) with an account switcher in the nav
/// bar and a footer of actions (Saved, Settings, Log out). When signed out it
/// shows a clean call-to-action to Log in or Sign up, with anonymous browsing
/// remaining the default.
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
        HasImageService &
        HasPostContentDetectorService &
        HasPreferencesService &
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

    // MARK: Private

    private let viewModel: AccountViewModel

    private var observationTask: Task<Void, Never>?

    /// The keychain id the current layout was built for, so the screen only
    /// rebuilds when the account or its sign-in state actually changes.
    private var renderedKeychainId: String?
    private var renderedSignedIn: Bool?
    private var renderedHasOwnPerson: Bool?

    private var currentChild: UIViewController?
    private var profileFooterView: AccountActionsFooterView?

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
                (viewModel.isSignedIn, viewModel.accountKeychainId, viewModel.ownPerson)
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

        // Rebuild only on a meaningful change. When signed in but the person
        // row hasn't been imported yet, rebuild once it appears so the embedded
        // profile can resolve.
        guard
            keychainId != renderedKeychainId ||
            signedIn != renderedSignedIn ||
            hasOwnPerson != renderedHasOwnPerson
        else { return }

        renderedKeychainId = keychainId
        renderedSignedIn = signedIn
        renderedHasOwnPerson = hasOwnPerson

        if signedIn {
            showSignedIn(keychainId: keychainId)
        } else {
            showSignedOut(keychainId: keychainId)
        }
    }

    // MARK: Layouts

    private func showSignedIn(keychainId: String) {
        configureNavBar(signedIn: true)

        guard let ownPerson = viewModel.ownPerson else {
            // Signed in but the person row hasn't landed yet (first login). Show
            // a spinner; the observation rebuilds when the import completes.
            showLoading()
            return
        }

        let personVC = PersonViewController(
            personRowId: ownPerson.personRowId,
            serverPersonId: Components.Schemas.PersonID(ownPerson.serverPersonId),
            accountKeychainId: keychainId,
            dependencies: dependencies.nested
        )

        // The profile occupies the screen above an account-actions footer
        // (Saved / Settings / Log out) pinned to the bottom safe area.
        let footer = AccountActionsFooterView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.savedTapped = { [weak self] in self?.openSaved(keychainId: keychainId) }
        footer.logoutTapped = { [weak self] in self?.confirmLogout() }
        profileFooterView = footer

        removeCurrentChild()

        add(child: personVC)
        let personView = personVC.view!
        personView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(personView)
        view.addSubview(footer)
        personVC.didMove(toParent: self)
        currentChild = personVC

        NSLayoutConstraint.activate([
            personView.topAnchor.constraint(equalTo: view.topAnchor),
            personView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            personView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            personView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Pin to the safe area, not the raw view bottom, so the footer (and
            // its Log out button) sits above the tab bar rather than under it.
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func showSignedOut(keychainId _: String) {
        configureNavBar(signedIn: false)

        let signedOutVC = AccountSignedOutViewController()
        signedOutVC.loginTapped = { [weak self] in self?.openLoginFlow() }
        signedOutVC.signUpTapped = { [weak self] in self?.openLoginFlow() }
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
        if let footer = profileFooterView {
            footer.removeFromSuperview()
            profileFooterView = nil
        }
        currentChild?.view.removeFromSuperview()
        remove(child: currentChild)
        currentChild = nil
    }

    // MARK: Nav bar

    private func configureNavBar(signedIn: Bool) {
        navigationItem.title = signedIn
            ? NSLocalizedString("Account", comment: "Account screen title when signed in")
            : NSLocalizedString("Account", comment: "Account screen title when signed out")

        // The account switcher is always available so the user can jump between
        // accounts (and add a new one) regardless of sign-in state.
        let switcher = UIBarButtonItem(
            image: UIImage(systemName: "person.2.crop.square.stack"),
            style: .plain,
            target: self,
            action: #selector(accountsTapped)
        )
        switcher.accessibilityLabel = NSLocalizedString("Switch account", comment: "Account switcher button accessibility label")
        navigationItem.rightBarButtonItem = switcher
    }

    // MARK: Actions

    @objc
    private func accountsTapped() {
        Haptics.tap()
        let accountListViewController = AccountListViewController(
            dependencies: dependencies.nested
        )
        let navigationController = UINavigationController(rootViewController: accountListViewController)
        present(navigationController, animated: true)
    }

    private func openSaved(keychainId: String) {
        Haptics.tap()
        let sortType = accountService.defaultSortType(forAccountKeychainId: keychainId)
        let feed = accountService.createFeed(
            forAccountKeychainId: keychainId,
            feedType: .saved(sortType: sortType)
        )
        let postListVC = PostListViewController(
            feed: feed,
            accountKeychainId: keychainId,
            dependencies: dependencies.nested
        )
        postListVC.navigationItem.title = NSLocalizedString("Saved", comment: "Saved posts screen title")
        navigationController?.pushViewController(postListVC, animated: true)
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
