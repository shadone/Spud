//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import OSLog
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import SwiftUI
import UIKit

private let logger = Logger.app

/// The Discover (Community Explorer) scene. A UIKit shell that owns the
/// navigation chrome (search + sort) and hosts ``DiscoverView`` (SwiftUI). Lives
/// under the Communities tab, reached from its "Explore communities" entry.
/// Tapping a community opens its page, where Subscribe lives.
class DiscoverViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase
    typealias NestedDependencies =
        CommunityOrLoadingViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    // MARK: Private

    private let accountKeychainId: String
    private var viewModel: DiscoverViewModel!

    // MARK: Functions

    init(
        accountKeychainId: String,
        isSignedIn: Bool,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.accountKeychainId = accountKeychainId

        super.init(nibName: nil, bundle: nil)

        viewModel = DiscoverViewModel(
            accountKeychainId: accountKeychainId,
            isSignedIn: isSignedIn,
            dependencies: dependencies,
            onOpenCommunity: { [weak self] row in
                self?.openCommunity(row)
            },
            onOpenPack: { [weak self] pack in
                self?.openPack(pack)
            },
            onRequestSignIn: { [weak self] in
                self?.presentSignInGate(
                    title: NSLocalizedString(
                        "Sign in to follow",
                        comment: "Sign-in gate title when a signed-out user taps Follow in Discover"
                    )
                )
            }
        )

        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        view.backgroundColor = Theme.background
        navigationItem.title = NSLocalizedString("Discover", comment: "Discover screen title")

        let accent = Color(ThemeManager.currentAccentColor)
        let contentVC = UIHostingController(rootView: DiscoverView(viewModel: viewModel, accent: accent))
        add(child: contentVC)
        addSubviewWithEdgeConstraints(child: contentVC)

        setupNavigationChrome()
    }

    private func setupNavigationChrome() {
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = NSLocalizedString(
            "Search all communities",
            comment: "Discover search placeholder"
        )
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false

        rebuildSortMenu()
    }

    private func rebuildSortMenu() {
        let actions = ExplorerCommunitySort.allCases.map { sort in
            UIAction(
                title: sort.title,
                state: viewModel.sort == sort ? .on : .off
            ) { [weak self] _ in
                self?.setSort(sort)
            }
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.up.arrow.down.circle"),
            menu: UIMenu(options: .singleSelection, children: actions)
        )
    }

    private func setSort(_ sort: ExplorerCommunitySort) {
        viewModel.sort = sort
        rebuildSortMenu()
    }

    private func openPack(_ pack: ResolvedStarterPack) {
        let accent = Color(ThemeManager.currentAccentColor)
        let detail = PackDetailView(
            pack: pack,
            accent: accent,
            onOpenCommunity: { [weak self] row in
                self?.openCommunity(row)
            }
        )
        let hosting = UIHostingController(rootView: detail)
        hosting.navigationItem.title = pack.title
        hosting.navigationItem.largeTitleDisplayMode = .never
        navigationController?.pushViewController(hosting, animated: true)
    }

    private func openCommunity(_ row: CommunityListRow) {
        guard let instance = InstanceActorId(from: "https://\(row.instanceHost)") else {
            logger.error("Discover: could not parse instance from \(row.instanceHost, privacy: .public)")
            return
        }
        let communityVC = CommunityOrLoadingViewController(
            communityName: row.name,
            instance: instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(communityVC, animated: true)
    }
}

extension DiscoverViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.searchText = searchController.searchBar.text ?? ""
    }
}
