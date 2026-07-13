//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog
import SpudDataKit
import SpudUIKit
import SwiftUI
import UIKit

private let logger = Logger.app

/// Hosts ``AccountSwitcherView`` as a bottom sheet (medium/large detents, with a
/// grabber and the sheet's own centered "Accounts" title — no nav bar). Reached
/// by tapping "Switch account" on the Account tab.
///
/// The `@Observable` view model keeps the SwiftUI list fed from
/// `observeAccountListRows()` and is handed straight to `AccountSwitcherView`, so
/// the sheet re-renders itself while it's open (e.g. after switching the default
/// account the radio check moves without re-presenting) — no relay loop here. The
/// four user actions route back through this controller:
/// - **select** -> `setDefaultAccount` + dismiss,
/// - **remove** (swipe, non-active rows only) -> `removeAccount`,
/// - **add account** -> the server picker (`SiteListViewController`),
/// - **browse anonymously** -> the same server picker, where the "Browse
///   anonymously" affordance lives (so we reuse the existing flow rather than
///   inventing a new entry point).
final class AccountListViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase &
        HasImageService
    typealias NestedDependencies =
        SiteListViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    private var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    private var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    // MARK: Private

    private let viewModel: AccountSwitcherViewModel

    // MARK: Functions

    init(dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)
        viewModel = AccountSwitcherViewModel(appDatabase: dependencies.appDatabase)

        super.init(nibName: nil, bundle: nil)

        // Force the draggable bottom-sheet presentation on every device. On iPad a
        // modal defaults to `.formSheet`, where `sheetPresentationController` is nil
        // and the grabber/detents never apply — pinning `.pageSheet` here, before
        // presentation, makes the controller a sheet (and the detents stick) on both
        // iPhone and iPad.
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // `.insetGrouped` styling drives its own background; this is the sheet's
        // base color so it reads correctly in light and dark (the old plain
        // `view.backgroundColor = .white` was broken in dark mode).
        view.backgroundColor = .systemGroupedBackground

        embedSwitcher()
        configureSheet()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Eagerly stop the DB observation when the sheet is dismissed so it
        // doesn't outlive the visible screen. The view model also cancels in
        // `deinit` as the reliable backstop.
        if isBeingDismissed {
            viewModel.stop()
        }
    }

    private func embedSwitcher() {
        // Hand the `@Observable` view model straight to the SwiftUI view: it reads
        // `viewModel.rows`, so SwiftUI re-renders itself on each DB emission. There
        // is no value-type `rootView` to re-push, hence no relay loop here.
        let switcher = AccountSwitcherView(
            viewModel: viewModel,
            accent: Color(ThemeManager.currentAccentColor),
            onSelect: { [weak self] keychainId in self?.selectAccount(keychainId: keychainId) },
            onRemove: { [weak self] keychainId in self?.removeAccount(keychainId: keychainId) },
            onReauth: { [weak self] keychainId in self?.reauth(keychainId: keychainId) },
            onAddAccount: { [weak self] in self?.addAccount() },
            onBrowseAnonymously: { [weak self] in self?.browseAnonymously() }
        )
        .environment(\.imageService, imageService)

        let hostingController = UIHostingController(rootView: switcher)
        add(child: hostingController)
        addSubviewWithEdgeConstraints(child: hostingController)
        hostingController.didMove(toParent: self)
    }

    /// Presents the switcher as a bottom sheet with medium and large detents and
    /// a visible grabber. The sheet carries its own title, so there is no nav
    /// bar wrapping this controller.
    private func configureSheet() {
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
    }

    // MARK: Actions

    /// Makes `keychainId` the default account and dismisses. The current
    /// `setDefaultAccount` is keychainId-only (no row record needed).
    private func selectAccount(keychainId: String) {
        Haptics.tap()
        accountService.setDefaultAccount(forAccountKeychainId: keychainId)
        dismiss(animated: true)
    }

    /// Removes an account and its keychain credential (if signed in). Only ever
    /// called for a non-active account — the switcher hides the swipe action on
    /// the active row — so the current default stays put and the app is never
    /// left without one. The observation then re-emits and the row drops out.
    private func removeAccount(keychainId: String) {
        accountService.removeAccount(forAccountKeychainId: keychainId)
    }

    /// Launches the in-place re-auth flow for the row's "Re-login" affordance,
    /// presented over the sheet itself (not dismissing it first, so the switcher
    /// is still there underneath if the user cancels).
    private func reauth(keychainId: String) {
        Haptics.tap()
        AccountReauthLauncher.present(
            forAccountKeychainId: keychainId,
            from: self,
            accountService: accountService,
            dependencies: dependencies.nested
        )
    }

    /// Opens the add-account flow: the server picker, then log in / sign up.
    private func addAccount() {
        Haptics.tap()
        presentServerPicker()
    }

    /// Opens the anonymous-browse flow. There is no standalone "browse
    /// anonymously" entry point: the affordance lives on the login screen
    /// reached through the server picker (pick a server -> "Browse <host>
    /// anonymously" -> confirmation -> `signInAsSignedOut`). Reusing that flow
    /// keeps a single path for choosing an instance.
    private func browseAnonymously() {
        Haptics.tap()
        presentServerPicker()
    }

    private func presentServerPicker() {
        let siteListViewController = SiteListViewController(
            dependencies: dependencies.nested
        )
        let navigationController = UINavigationController(rootViewController: siteListViewController)
        present(navigationController, animated: true)
    }
}
